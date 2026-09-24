# frozen_string_literal: true

RSpec.describe "error handling" do
  let(:client) { build_client }
  let(:retrying_client) { build_client(max_retries: 2) }
  let(:identity_url) { "#{BASE_URL}/identities/user_12345" }

  def error_body(status, message)
    { "timestamp" => "2026-09-21T14:22:09Z", "status" => status, "error" => "Error", "message" => message }
  end

  describe "status mapping" do
    {
      400 => Dregs::BadRequestError,
      401 => Dregs::AuthenticationError,
      402 => Dregs::QuotaExceededError,
      403 => Dregs::PermissionDeniedError,
      404 => Dregs::NotFoundError,
      429 => Dregs::RateLimitError,
      500 => Dregs::ServerError,
      503 => Dregs::ServerError
    }.each do |status, expected|
      it "raises #{expected} on #{status}" do
        stub_json(:get, "/identities/user_12345", error_body(status, "No"), status: status)

        expect { client.identities.get("user_12345") }
          .to raise_error(expected) { |error| expect(error.status_code).to eq(status) }
      end
    end

    it "falls back to the base class on an unmapped 4xx" do
      stub_json(:get, "/identities/user_12345", error_body(418, "No"), status: 418)

      expect { client.identities.get("user_12345") }.to raise_error(Dregs::APIError)
    end

    it "makes every error catchable as Dregs::Error" do
      stub_json(:get, "/identities/user_12345", nil, status: 404)

      expect { client.identities.get("user_12345") }.to raise_error(Dregs::Error)
    end

    it "carries the API's message through" do
      stub_json(:get, "/identities/user_12345", error_body(404, "Not Found"), status: 404)

      expect { client.identities.get("user_12345") }
        .to raise_error(Dregs::NotFoundError) { |error| expect(error.api_message).to eq("Not Found") }
    end

    it "prefixes the status in the message" do
      stub_json(:get, "/identities/user_12345", error_body(404, "Not Found"), status: 404)

      expect { client.identities.get("user_12345") }.to raise_error(/HTTP 404: Not Found/)
    end

    it "carries the request id through" do
      stub_json(:get, "/identities/user_12345", nil, status: 500, headers: { "X-Request-Id" => "req_abc" })

      expect { client.identities.get("user_12345") }
        .to raise_error(Dregs::ServerError) { |error| expect(error.request_id).to eq("req_abc") }
    end

    it "mentions the request id in the message" do
      stub_json(:get, "/identities/user_12345", nil, status: 500, headers: { "X-Request-Id" => "req_abc" })

      expect { client.identities.get("user_12345") }.to raise_error(/req_abc/)
    end

    it "still raises the right class when the body is not JSON" do
      stub_request(:get, identity_url).to_return(status: 502, body: "<html>gateway</html>")

      expect { client.identities.get("user_12345") }
        .to raise_error(Dregs::ServerError) { |error| expect(error.body).to be_nil }
    end

    it "keeps the parsed body on the error" do
      stub_json(:get, "/identities/user_12345", error_body(400, "Bad"), status: 400)

      expect { client.identities.get("user_12345") }
        .to raise_error(Dregs::BadRequestError) { |error| expect(error.body["message"]).to eq("Bad") }
    end
  end

  describe "rate limits and quotas" do
    it "exposes Retry-After" do
      stub_request(:post, "#{BASE_URL}/events")
        .to_return(status: 429, headers: { "Retry-After" => "2" }, body: '{"status":"rate_limited"}')

      expect { client.track("user.signup", identity: "user_12345") }
        .to raise_error(Dregs::RateLimitError) { |error| expect(error.retry_after).to eq(2.0) }
    end

    it "leaves retry_after nil when the header is an HTTP date" do
      stub_request(:post, "#{BASE_URL}/events")
        .to_return(status: 429, headers: { "Retry-After" => "Mon, 21 Sep 2026 14:22:09 GMT" }, body: "{}")

      expect { client.track("user.signup", identity: "user_12345") }
        .to raise_error(Dregs::RateLimitError) { |error| expect(error.retry_after).to be_nil }
    end

    it "raises on a rate limit reported in a 200 body" do
      capture_events({ "status" => "rate_limited", "id" => nil })

      expect { client.track("user.signup", identity: "user_12345") }.to raise_error(Dregs::RateLimitError)
    end

    it "raises on a quota reported in a 200 body" do
      capture_events({ "status" => "quota_exceeded", "id" => nil })

      expect { client.track("user.signup", identity: "user_12345") }
        .to raise_error(Dregs::QuotaExceededError) { |error| expect(error.status_code).to eq(402) }
    end

    it "does not mistake a success body for a legacy status" do
      capture_events

      expect(client.track("user.signup", identity: "user_12345").accepted?).to be(true)
    end
  end

  describe "retries" do
    it "retries a server error and can succeed" do
      stub_request(:get, identity_url).to_return(
        { status: 503, body: "" },
        { status: 200, body: '{"id":"user_12345"}' }
      )

      expect(retrying_client.identities.get("user_12345").id).to eq("user_12345")
      expect(WebMock).to have_requested(:get, identity_url).twice
    end

    it "stops at the configured retry limit" do
      stub_request(:get, identity_url).to_return(status: 500, body: "")

      expect { retrying_client.identities.get("user_12345") }.to raise_error(Dregs::ServerError)
      expect(WebMock).to have_requested(:get, identity_url).times(3)
    end

    it "retries a rate limit" do
      stub_request(:post, "#{BASE_URL}/events").to_return(
        { status: 429, headers: { "Retry-After" => "0" }, body: "" },
        { status: 200, body: ACCEPTED_EVENT.to_json }
      )

      expect(retrying_client.track("user.signup", identity: "user_12345").accepted?).to be(true)
      expect(WebMock).to have_requested(:post, "#{BASE_URL}/events").twice
    end

    it "retries a 408" do
      stub_request(:get, identity_url).to_return(
        { status: 408, body: "" },
        { status: 200, body: '{"id":"user_12345"}' }
      )

      expect(retrying_client.identities.get("user_12345").id).to eq("user_12345")
    end

    it "keeps the event id across a retry so ingestion stays idempotent" do
      bodies = []

      stub_request(:post, "#{BASE_URL}/events").to_return do |request|
        bodies << JSON.parse(request.body)

        bodies.size == 1 ? { status: 503, body: "" } : { status: 200, body: ACCEPTED_EVENT.to_json }
      end

      retrying_client.track("user.signup", identity: "user_12345")

      expect(bodies.map { |body| body["id"] }.uniq.size).to eq(1)
    end

    it "does not retry a client error" do
      stub_request(:get, identity_url).to_return(status: 404, body: "")

      expect { retrying_client.identities.get("user_12345") }.to raise_error(Dregs::NotFoundError)
      expect(WebMock).to have_requested(:get, identity_url).once
    end

    it "does not retry at all when max_retries is zero" do
      stub_request(:get, identity_url).to_return(status: 500, body: "")

      expect { client.identities.get("user_12345") }.to raise_error(Dregs::ServerError)
      expect(WebMock).to have_requested(:get, identity_url).once
    end

    it "retries a connection failure and then raises" do
      stub_request(:get, identity_url).to_raise(Errno::ECONNREFUSED)

      expect { retrying_client.identities.get("user_12345") }.to raise_error(Dregs::ConnectionError)
      expect(WebMock).to have_requested(:get, identity_url).times(3)
    end

    it "recovers when a retry after a connection failure lands" do
      stub = stub_request(:get, identity_url)
      stub.to_raise(Errno::ECONNREFUSED).then.to_return(status: 200, body: '{"id":"user_12345"}')

      expect(retrying_client.identities.get("user_12345").id).to eq("user_12345")
    end

    it "raises a timeout error of its own" do
      stub_request(:get, identity_url).to_timeout

      expect { client.identities.get("user_12345") }.to raise_error(Dregs::TimeoutError)
    end

    it "treats a timeout as a connection error for rescuing purposes" do
      stub_request(:get, identity_url).to_timeout

      expect { client.identities.get("user_12345") }.to raise_error(Dregs::ConnectionError)
    end

    it "retries a timeout" do
      stub = stub_request(:get, identity_url)
      stub.to_timeout.then.to_return(status: 200, body: '{"id":"user_12345"}')

      expect(retrying_client.identities.get("user_12345").id).to eq("user_12345")
    end
  end

  describe "backoff" do
    let(:unstubbed) { Dregs::Client.new(secret_key: SECRET_KEY, base_url: BASE_URL) }

    it "honours Retry-After over its own jitter" do
      expect(unstubbed.send(:backoff, 0, 3.0)).to eq(3.0)
    end

    it "caps a wildly long Retry-After" do
      expect(unstubbed.send(:backoff, 0, 9_000.0)).to eq(Dregs::Client::MAX_BACKOFF_SECONDS)
    end

    it "grows with the attempt number" do
      expect(unstubbed.send(:backoff, 4, nil)).to be <= 8.0
    end

    it "stays non-negative" do
      expect(unstubbed.send(:backoff, 0, nil)).to be >= 0
    end
  end
end
