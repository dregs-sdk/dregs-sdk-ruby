# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "timeout"
require "uri"

require_relative "errors"
require_relative "identities"
require_relative "models"
require_relative "version"

module Dregs
  # A Dregs client.
  #
  # The secret key comes from the +DREGS_SECRET_KEY+ environment variable unless you pass one.
  # Find it under *Settings -> Credentials* in the dashboard; it is the key starting +sk_+, not
  # the +pk_+ public key the browser tracker uses.
  #
  #   client = Dregs::Client.new
  #
  #   client.track("user.signup", identity: "user_12345", data: { plan: "pro" })
  #
  #   scores = client.identities.scores("user_12345")
  #
  # Build one at startup and keep it. The client holds no connection state of its own, so it is
  # safe to share across threads and to call from a background job.
  class Client
    # Where requests go when neither an argument nor +DREGS_BASE_URL+ says otherwise.
    DEFAULT_BASE_URL = "https://dregs.com/api"

    # Seconds before a request is abandoned, for both connecting and reading.
    DEFAULT_TIMEOUT = 10

    # How many times a failed request is retried before its error is raised.
    DEFAULT_MAX_RETRIES = 2

    # The environment variable the secret key is read from.
    SECRET_KEY_ENV = "DREGS_SECRET_KEY"

    # The environment variable the base URL is read from.
    BASE_URL_ENV = "DREGS_BASE_URL"

    # Statuses worth another attempt. 429 and 5xx are transient by definition; 408 shows up in
    # front of some proxies.
    RETRY_STATUSES = [408, 429, 500, 502, 503, 504].freeze

    # The longest this client will wait between attempts, however long +Retry-After+ asks for.
    MAX_BACKOFF_SECONDS = 60.0

    # Body-level statuses Dregs uses on +POST /api/events+.
    STATUS_RATE_LIMITED = "rate_limited"
    STATUS_QUOTA_EXCEEDED = "quota_exceeded"

    # @return [String] the API root every request is built against, without a trailing slash
    attr_reader :base_url

    # @return [Integer] how many times a failed request is retried
    attr_reader :max_retries

    # @return [Numeric] seconds before a request is abandoned
    attr_reader :timeout

    # @return [Identities] read identities, their scores, and their analysis
    attr_reader :identities

    # @param secret_key [String, nil] your credential's secret key; defaults to +$DREGS_SECRET_KEY+
    # @param base_url [String, nil] the API root; defaults to +$DREGS_BASE_URL+, then
    #   {DEFAULT_BASE_URL}
    # @param timeout [Numeric] seconds before a request is abandoned, applied to connecting,
    #   writing, and reading alike
    # @param max_retries [Integer] how many times to retry a failed request. Retries cover
    #   connection failures, timeouts, 429s, and 5xx, with exponential backoff and jitter; the
    #   +Retry-After+ header wins when the server sends one. Pass 0 to handle it yourself.
    # @raise [ArgumentError] when no secret key is available, when the key is a +pk_+ public key,
    #   or when +max_retries+ is negative
    def initialize(secret_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES)
      resolved_key = secret_key || ENV.fetch(SECRET_KEY_ENV, nil)

      raise ArgumentError, missing_key_message if resolved_key.nil? || resolved_key.empty?
      raise ArgumentError, public_key_message if resolved_key.start_with?("pk_")
      raise ArgumentError, "max_retries cannot be negative." if max_retries.negative?

      @secret_key = resolved_key
      @base_url = (base_url || ENV.fetch(BASE_URL_ENV, nil) || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
      @timeout = timeout
      @max_retries = max_retries
      @identities = Identities.new(self)
    end

    # Records a backend event against an identity.
    #
    #   client.track(
    #     "user.signup",
    #     identity: "user_12345",
    #     data: { plan: "pro", referrer: "partner-x" },
    #     identity_data: { email: "ada@example.com", name: "Ada Lovelace" }
    #   )
    #
    # @param event_type [String] your name for the event, such as +"user.signup"+. Map it to one
    #   of Dregs's canonical types under *Settings -> Mappings* so the analyzers know what it
    #   means.
    # @param identity [String] your own id for the user. This is the same id you pass to
    #   +dregs.identify()+ in the browser tracker, and the one you look scores up by. It is
    #   required: a server-side event carries no device signature, so the identity is the only
    #   thing tying it to a user.
    # @param data [Hash] attributes of the event itself
    # @param identity_data [Hash] attributes of the *user*, such as email, name, or username.
    #   Dregs merges these into the identity, and the analyzers lean on them heavily, so send them
    #   whenever you have them. Flat keys work best; name them as your application already does
    #   and map them under *Settings -> Mappings*.
    # @param event_id [String, nil] your own id for the event, which makes ingestion idempotent:
    #   reposting the same id returns the original event instead of recording a second one. Pass
    #   the id your application already has (the row id of the record that triggered the event,
    #   say). When you omit it the SDK generates one, which is what makes its own retries safe. At
    #   most 64 characters, and it cannot start with +dregs-+.
    # @param timestamp [Time, DateTime, String, nil] when the event happened, if not now. A +Time+
    #   is converted to UTC; a string is sent as given and must already be ISO-8601.
    # @param source [String, nil] a label for where the event came from; defaults to +"ruby-sdk"+
    # @return [TrackResult] check +accepted?+ to confirm Dregs recorded the event
    # @raise [QuotaExceededError] the account is over its monthly event limit
    # @raise [RateLimitError] the credential is ingesting too fast
    # @raise [AuthenticationError] the secret key was not recognized
    # @raise [BadRequestError] the event was malformed
    # @raise [ArgumentError] the event type, identity, or event id was unusable
    def track(event_type, identity:, data: {}, identity_data: {}, event_id: nil, timestamp: nil, source: nil)
      body = track_body(
        event_type,
        identity: identity,
        data: data,
        identity_data: identity_data,
        event_id: event_id,
        timestamp: timestamp,
        source: source
      )

      TrackResult.from_api(request(:post, "/events", body: body))
    end

    # Performs a request, retrying the failures worth retrying.
    #
    # @api private
    # @param method [Symbol] +:get+ or +:post+
    # @param path [String] the path below the base URL, with a leading slash
    # @param body [Hash, nil] a JSON body, for POSTs that carry one
    # @return [Hash, Array, nil] the parsed response body
    def request(method, path, body: nil)
      uri = URI.parse(url_for(path))
      attempt = 0

      loop do
        outcome = attempt_request(uri, method, body, attempt)

        return outcome.fetch(:payload) if outcome.key?(:payload)

        sleep(backoff(attempt, outcome[:retry_after]))
        attempt += 1
      end
    end

    private

    # One attempt, returning either the parsed payload or a note that we should try again.
    #
    # Whether a failure is worth retrying is decided here, next to the failure, so the loop above
    # stays readable: anything this returns without a +:payload+ key has already been judged
    # retryable, and anything not worth retrying has already been raised.
    def attempt_request(uri, method, body, attempt)
      response = perform(uri, method, body)

      begin
        { payload: process(response) }
      rescue APIError => e
        raise unless retry?(attempt: attempt, status_code: e.status_code)

        { retry_after: e.is_a?(RateLimitError) ? e.retry_after : nil }
      end
    rescue Timeout::Error
      raise TimeoutError, "Request to #{uri} timed out." unless retry?(attempt: attempt, status_code: nil)

      {}
    rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
      raise ConnectionError, unreachable(uri, e) unless retry?(attempt: attempt, status_code: nil)

      {}
    end

    def unreachable(uri, error)
      "Could not reach Dregs at #{uri}: #{error.message}"
    end

    def missing_key_message
      "No Dregs secret key. Pass secret_key: ... or set the #{SECRET_KEY_ENV} environment " \
        "variable. You will find your credential's secret key under Settings -> Credentials in " \
        "the Dregs dashboard."
    end

    def public_key_message
      "That is a public key. The public key is for the browser tracker and cannot read " \
        "identities or scores; this SDK needs the secret key from the same credential, which " \
        "starts with 'sk_'."
    end

    # Builds the +POST /api/events+ body.
    #
    # An event id is always sent. When the caller has an id of their own it is used verbatim, so
    # reposting the same event is a no-op on the Dregs side; otherwise one is generated, which is
    # what makes this client's own retries safe to perform.
    def track_body(event_type, identity:, data:, identity_data:, event_id:, timestamp:, source:)
      raise ArgumentError, "event_type is required." if event_type.nil? || event_type.to_s.empty?

      if identity.nil? || identity.to_s.empty?
        raise ArgumentError,
              "identity is required. A server-side event has no device signature, so the " \
              "identity is the only thing tying the event to a user."
      end

      resolved_id = event_id || SecureRandom.uuid.delete("-")

      if resolved_id.start_with?("dregs-")
        raise ArgumentError, "Event ids starting with 'dregs-' are reserved for Dregs itself."
      end

      raise ArgumentError, "Event ids cannot be longer than 64 characters." if resolved_id.length > 64

      body = {
        "id" => resolved_id,
        "type" => event_type.to_s,
        "data" => data || {},
        "identity" => { "id" => identity.to_s, "data" => identity_data || {} },
        "source" => source || "ruby-sdk"
      }

      body["timestamp"] = iso8601(timestamp) unless timestamp.nil?

      body
    end

    # Formats a timestamp the way the API's +Instant+ parser expects.
    #
    # A +Time+ is converted to UTC rather than sent with its offset, and a string is trusted as
    # already being ISO-8601 — a caller who has one in hand should not have to parse it just so
    # this method can format it again.
    def iso8601(value)
      return value if value.is_a?(String)
      return value.to_time.getutc.strftime("%Y-%m-%dT%H:%M:%SZ") if value.respond_to?(:to_time)

      raise ArgumentError, "timestamp must be a Time, a DateTime, or an ISO-8601 string."
    end

    def url_for(path)
      "#{base_url}/#{path.sub(%r{\A/+}, "")}"
    end

    def headers
      {
        "Authorization" => "Bearer #{@secret_key}",
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => user_agent
      }
    end

    def user_agent
      "dregs-ruby/#{Dregs::VERSION} (ruby #{RUBY_VERSION})"
    end

    def perform(uri, method, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout

      request = build_request(uri, method)
      headers.each { |name, value| request[name] = value }
      request.body = JSON.generate(body) if body

      http.start { |connection| connection.request(request) }
    end

    def build_request(uri, method)
      case method
      when :get then Net::HTTP::Get.new(uri)
      when :post then Net::HTTP::Post.new(uri)
      else raise ArgumentError, "Unsupported HTTP method: #{method}."
      end
    end

    def retry?(attempt:, status_code:)
      return false if attempt >= max_retries

      status_code.nil? || RETRY_STATUSES.include?(status_code)
    end

    # Seconds to wait before the next attempt.
    #
    # +Retry-After+ wins when the server sent one. Otherwise this is exponential with full jitter,
    # which keeps a fleet of workers that all hit the limit at once from retrying in lockstep.
    def backoff(attempt, retry_after)
      return [retry_after, MAX_BACKOFF_SECONDS].min if retry_after && retry_after >= 0

      rand * [0.5 * (2**attempt), 8.0].min
    end

    # Turns a response into parsed JSON, or raises the matching error.
    def process(response)
      payload = json_or_nil(response)
      status = response.code.to_i

      raise api_error(response, payload, status) if status >= 400

      # An older API build reported both of these as HTTP 200 with the outcome in the body.
      # Reading the body as well as the status keeps this SDK correct against either.
      check_body_status(response, payload) if payload.is_a?(Hash)

      payload
    end

    def check_body_status(response, payload)
      case payload["status"]
      when STATUS_RATE_LIMITED
        raise RateLimitError.new(
          "Ingestion rate limit exceeded for this credential.",
          body: payload,
          request_id: request_id(response),
          retry_after: retry_after(response)
        )
      when STATUS_QUOTA_EXCEEDED
        raise QuotaExceededError.new(
          "The account is over its monthly event limit.",
          status_code: 402,
          body: payload,
          request_id: request_id(response)
        )
      end
    end

    def api_error(response, payload, status)
      message = message_from(payload) || response.message.to_s
      message = "Request failed" if message.empty?

      return rate_limit_error(response, payload, message) if status == 429

      Errors.for_status(status).new(
        message,
        status_code: status,
        body: payload,
        request_id: request_id(response)
      )
    end

    def rate_limit_error(response, payload, message)
      RateLimitError.new(
        message,
        body: payload,
        request_id: request_id(response),
        retry_after: retry_after(response)
      )
    end

    def message_from(payload)
      return nil unless payload.is_a?(Hash)

      %w[message error status].each do |key|
        value = payload[key]

        return value if value.is_a?(String) && !value.empty?
      end

      nil
    end

    def json_or_nil(response)
      body = response.body

      return nil if body.nil? || body.empty?

      begin
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end
    end

    def request_id(response)
      response["X-Request-Id"]
    end

    # The header also allows an HTTP date, which is rare enough here that falling back to the
    # client's own backoff beats dragging in a date parser.
    def retry_after(response)
      raw = response["Retry-After"]

      return nil if raw.nil?

      Float(raw, exception: false)
    end
  end
end
