# frozen_string_literal: true

require "json"
require "openssl"
require "time"

require_relative "errors"

module Dregs
  # Verifying webhooks Dregs sends you.
  #
  # Dregs signs every webhook with the channel's signing secret: +X-Dregs-Signature+ is the
  # hex-encoded HMAC-SHA256 of the raw request body. Verify it before you act on the payload, and
  # verify it against the bytes you received rather than a re-serialized hash, because
  # re-serializing changes key order and whitespace and will not match.
  #
  #   post "/webhooks/dregs" do
  #     event = Dregs::Webhooks.verify(
  #       payload: request.body.read,
  #       signature: request.env["HTTP_X_DREGS_SIGNATURE"],
  #       secret: ENV.fetch("DREGS_WEBHOOK_SECRET")
  #     )
  #
  #     handle(event)
  #   rescue Dregs::WebhookVerificationError
  #     halt 400
  #   end
  #
  # In Rails that raw body is +request.raw_post+; in Rack it is +request.body.read+, and you may
  # need to +rewind+ the body if something downstream reads it again.
  #
  # The signing secret is shown once, when you create the webhook channel. It is not your API
  # secret key: one authenticates you to Dregs, the other proves a payload came from Dregs.
  module Webhooks
    # The header carrying the signature.
    SIGNATURE_HEADER = "X-Dregs-Signature"

    # The header carrying the delivery's timestamp. The signed body carries its own copy, which is
    # the one {verify} checks, because a header can be edited without breaking the signature.
    TIMESTAMP_HEADER = "X-Dregs-Timestamp"

    # The header naming the event type.
    EVENT_HEADER = "X-Dregs-Event"

    # How far out of date a webhook's timestamp may be, in seconds, before {verify} rejects it.
    DEFAULT_TOLERANCE_SECONDS = 300

    module_function

    # Returns the hex-encoded HMAC-SHA256 of +payload+ under +secret+.
    #
    # @param payload [String] the raw request body
    # @param secret [String] the channel's signing secret
    # @return [String]
    def compute_signature(payload:, secret:)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, payload.to_s)
    end

    # Returns whether +signature+ matches +payload+.
    #
    # The comparison is constant-time. Prefer {verify}, which also rejects replays and hands back
    # the parsed event; reach for this one only when you need the boolean.
    #
    # @param payload [String] the raw request body, exactly as received
    # @param signature [String] the +X-Dregs-Signature+ header
    # @param secret [String] the channel's signing secret
    # @return [Boolean]
    def verify_signature(payload:, signature:, secret:)
      return false if signature.nil? || signature.to_s.strip.empty?
      return false if secret.nil? || secret.to_s.empty?

      OpenSSL.secure_compare(compute_signature(payload: payload, secret: secret), signature.to_s.strip)
    end

    # Verifies a webhook and returns its parsed body.
    #
    # @param payload [String] the raw request body, exactly as received. Not a parsed hash.
    # @param signature [String] the +X-Dregs-Signature+ header
    # @param secret [String] the channel's signing secret
    # @param tolerance [Numeric, nil] how many seconds out of date the payload's own +timestamp+
    #   may be before it is treated as a replay. Pass nil to skip the check, which you should only
    #   do if you are deduplicating on the event id yourself. The timestamp is inside the signed
    #   body, so an attacker cannot alter it without breaking the signature.
    # @param now [Time, nil] the current time, for tests
    # @return [Hash] the parsed webhook body: +"event"+, +"timestamp"+, and the payload for that
    #   event, with string keys exactly as Dregs sent them
    # @raise [WebhookVerificationError] the signature did not match, the body was not a JSON
    #   object, or the payload is older than +tolerance+
    def verify(payload:, signature:, secret:, tolerance: DEFAULT_TOLERANCE_SECONDS, now: nil)
      unless verify_signature(payload: payload, signature: signature, secret: secret)
        raise WebhookVerificationError,
              "The webhook signature did not match. Check that you are verifying the raw request " \
              "body rather than a re-serialized copy, and that the signing secret belongs to the " \
              "channel that sent this delivery."
      end

      event = parse(payload)

      check_freshness(event, tolerance: tolerance, now: now) unless tolerance.nil?

      event
    end

    # @api private
    def parse(payload)
      event =
        begin
          JSON.parse(payload.to_s)
        rescue JSON::ParserError => e
          raise WebhookVerificationError, "The webhook body was not valid JSON: #{e.message}"
        end

      raise WebhookVerificationError, "The webhook body was not a JSON object." unless event.is_a?(Hash)

      event
    end

    # @api private
    def check_freshness(event, tolerance:, now:)
      raw = event["timestamp"]

      if !raw.is_a?(String) || raw.empty?
        raise WebhookVerificationError,
              "The webhook carried no timestamp, so it cannot be checked for replay. Pass " \
              "tolerance: nil if you are deduplicating deliveries some other way."
      end

      sent =
        begin
          Time.iso8601(raw)
        rescue ArgumentError
          raise WebhookVerificationError, "The webhook timestamp was unreadable: #{raw.inspect}"
        end

      age = ((now || Time.now).getutc - sent.getutc).abs

      return if age <= tolerance

      raise WebhookVerificationError,
            "The webhook timestamp is #{age.round}s away from now, beyond the #{tolerance.round}s " \
            "tolerance. Treating it as a replay."
    end
  end
end
