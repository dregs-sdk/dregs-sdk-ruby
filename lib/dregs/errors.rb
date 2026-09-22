# frozen_string_literal: true

module Dregs
  # Base class for everything this library raises.
  #
  # A caller who only wants a coarse "the Dregs call failed" branch can rescue this one class.
  # Errors that came back from the API derive from {APIError} and carry the HTTP status and the
  # parsed body; errors that never reached the API (DNS, a refused connection, a timeout) derive
  # from {ConnectionError} instead.
  #
  # Programmer mistakes — a missing secret key, an event id longer than the API allows — raise
  # +ArgumentError+ rather than one of these, because they are bugs to fix rather than conditions
  # to handle at runtime.
  class Error < StandardError; end

  # The request never reached Dregs: DNS, TCP, TLS, or a dropped connection.
  #
  # Retrying is usually the right response, and the client already does so; seeing this means the
  # retries were exhausted too.
  class ConnectionError < Error; end

  # The request was still outstanding when the configured timeout elapsed.
  #
  # The event may or may not have been recorded. Because every event is sent with an id, reposting
  # it is safe: Dregs returns the original event rather than recording a second one.
  class TimeoutError < ConnectionError; end

  # An incoming webhook did not verify against the channel's signing secret.
  #
  # Answer the delivery with a 4xx and do not act on the payload.
  class WebhookVerificationError < Error; end

  # Dregs answered, and the answer was an error.
  #
  # @!attribute [r] status_code
  #   @return [Integer] the HTTP status code
  # @!attribute [r] body
  #   @return [Hash, Array, nil] the parsed JSON body, or nil when the response was not JSON
  # @!attribute [r] request_id
  #   @return [String, nil] the +X-Request-Id+ response header, worth quoting in a support request
  # @!attribute [r] api_message
  #   @return [String] the message as Dregs phrased it, without the status prefix {#to_s} adds
  class APIError < Error
    attr_reader :status_code, :body, :request_id, :api_message

    # @param message [String] the human-readable message, from the response body when it carried one
    # @param status_code [Integer] the HTTP status code
    # @param body [Hash, Array, nil] the parsed JSON body
    # @param request_id [String, nil] the +X-Request-Id+ response header
    def initialize(message, status_code:, body: nil, request_id: nil)
      super(message)

      @api_message = message
      @status_code = status_code
      @body = body
      @request_id = request_id
    end

    # @return [String] the message, prefixed with the status and suffixed with the request id
    def to_s
      suffix = request_id ? " (request #{request_id})" : ""

      "HTTP #{status_code}: #{api_message}#{suffix}"
    end
  end

  # 400. The request was malformed or missing something Dregs requires.
  #
  # For event ingestion this most often means the event carried neither an identity nor a device,
  # or the body failed validation. Retrying unchanged will not help.
  class BadRequestError < APIError; end

  # 401. The secret key was missing, unrecognized, revoked, or expired.
  #
  # Check that the key is the +sk_+ secret key rather than the +pk_+ public key, and that it has
  # not been revoked under Settings -> Credentials.
  class AuthenticationError < APIError; end

  # 402. The account is over its monthly event limit and ingestion is refused.
  #
  # Events are not queued while an account is over its limit, so the caller decides whether to drop
  # the event or hold it. The limit resets with the billing period; upgrading the plan clears it
  # immediately.
  class QuotaExceededError < APIError; end

  # 403. The credential authenticated but is not allowed to do this.
  class PermissionDeniedError < APIError; end

  # 404. No such identity, or no analysis has been run for it yet.
  #
  # An identity appears the first time you track an event for it, and an analysis cycle appears
  # shortly after that, so a 404 on a brand-new user is expected rather than alarming.
  class NotFoundError < APIError; end

  # 429. The credential exceeded its request rate limit.
  #
  # @!attribute [r] retry_after
  #   @return [Float, nil] seconds to wait before retrying, from the +Retry-After+ header
  class RateLimitError < APIError
    attr_reader :retry_after

    # @param message [String] the human-readable message
    # @param status_code [Integer] the HTTP status code, 429 unless an older build reported it in
    #   the response body
    # @param body [Hash, Array, nil] the parsed JSON body
    # @param request_id [String, nil] the +X-Request-Id+ response header
    # @param retry_after [Float, nil] seconds to wait, when the server said how long
    def initialize(message, status_code: 429, body: nil, request_id: nil, retry_after: nil)
      super(message, status_code: status_code, body: body, request_id: request_id)

      @retry_after = retry_after
    end
  end

  # 5xx. Something went wrong inside Dregs. These are retried automatically.
  class ServerError < APIError; end

  # Maps HTTP statuses to the error class that represents them.
  module Errors
    STATUS_ERRORS = {
      400 => BadRequestError,
      401 => AuthenticationError,
      402 => QuotaExceededError,
      403 => PermissionDeniedError,
      404 => NotFoundError,
      429 => RateLimitError
    }.freeze

    # Returns the exception class that represents +status_code+.
    #
    # Anything at or above 500 is a {ServerError}; an unmapped 4xx falls back to the {APIError}
    # base class rather than raising something this SDK cannot name.
    #
    # @param status_code [Integer]
    # @return [Class]
    def self.for_status(status_code)
      return STATUS_ERRORS.fetch(status_code) if STATUS_ERRORS.key?(status_code)
      return ServerError if status_code >= 500

      APIError
    end
  end
end
