# frozen_string_literal: true

RSpec.describe Dregs::Webhooks do
  let(:secret) { "whsec_abc123" }
  let(:sent_at) { Time.utc(2026, 9, 21, 14, 22, 9) }
  let(:payload) { body }

  def body(overrides = {})
    {
      "event" => "ESCALATION_CREATED",
      "timestamp" => "2026-09-21T14:22:09Z",
      "identityId" => "user_12345"
    }.merge(overrides).to_json
  end

  def sign(raw, key = secret)
    OpenSSL::HMAC.hexdigest("SHA256", key, raw)
  end

  def verify_at(moment)
    described_class.verify(payload: payload, signature: sign(payload), secret: secret, now: moment)
  end

  describe ".compute_signature" do
    it "matches a hand-rolled HMAC" do
      expect(described_class.compute_signature(payload: payload, secret: secret)).to eq(sign(payload))
    end

    it "is hex-encoded SHA256, so 64 characters" do
      expect(described_class.compute_signature(payload: payload, secret: secret).length).to eq(64)
    end

    it "changes when the body changes" do
      other = described_class.compute_signature(payload: body("identityId" => "someone"), secret: secret)

      expect(other).not_to eq(sign(payload))
    end
  end

  describe ".verify_signature" do
    it "accepts a good signature" do
      expect(described_class.verify_signature(payload: payload, signature: sign(payload), secret: secret))
        .to be(true)
    end

    it "tolerates surrounding whitespace" do
      signature = "  #{sign(payload)}\n"

      expect(described_class.verify_signature(payload: payload, signature: signature, secret: secret))
        .to be(true)
    end

    it "rejects a tampered body" do
      tampered = body("identityId" => "someone_else")

      expect(described_class.verify_signature(payload: tampered, signature: sign(payload), secret: secret))
        .to be(false)
    end

    it "rejects the wrong secret" do
      signature = sign(payload, "whsec_other")

      expect(described_class.verify_signature(payload: payload, signature: signature, secret: secret))
        .to be(false)
    end

    it "rejects an empty signature" do
      expect(described_class.verify_signature(payload: payload, signature: "", secret: secret)).to be(false)
    end

    it "rejects a nil signature" do
      expect(described_class.verify_signature(payload: payload, signature: nil, secret: secret)).to be(false)
    end

    it "rejects an empty secret" do
      expect(described_class.verify_signature(payload: payload, signature: sign(payload), secret: ""))
        .to be(false)
    end

    it "rejects a signature of the wrong length rather than raising" do
      expect(described_class.verify_signature(payload: payload, signature: "abc", secret: secret))
        .to be(false)
    end
  end

  describe ".verify" do
    it "returns the parsed event" do
      event = described_class.verify(payload: payload, signature: sign(payload), secret: secret, now: sent_at)

      expect(event["event"]).to eq("ESCALATION_CREATED")
      expect(event["identityId"]).to eq("user_12345")
    end

    it "raises on a bad signature" do
      expect { described_class.verify(payload: payload, signature: "deadbeef", secret: secret, now: sent_at) }
        .to raise_error(Dregs::WebhookVerificationError, /signature/)
    end

    it "says to check the raw body when the signature fails" do
      expect { described_class.verify(payload: payload, signature: "deadbeef", secret: secret, now: sent_at) }
        .to raise_error(/raw request body/)
    end

    it "raises when the body is not JSON" do
      raw = "not json at all"

      expect { described_class.verify(payload: raw, signature: sign(raw), secret: secret) }
        .to raise_error(Dregs::WebhookVerificationError, /JSON/)
    end

    it "raises when the body is a JSON array" do
      raw = "[1, 2, 3]"

      expect { described_class.verify(payload: raw, signature: sign(raw), secret: secret) }
        .to raise_error(Dregs::WebhookVerificationError, /JSON object/)
    end

    it "refuses a stale payload as a replay" do
      expect { verify_at(sent_at + 3600) }.to raise_error(Dregs::WebhookVerificationError, /replay/)
    end

    it "refuses a payload from the future too" do
      expect { verify_at(sent_at - 3600) }.to raise_error(Dregs::WebhookVerificationError, /replay/)
    end

    it "accepts a payload inside the tolerance" do
      event = described_class.verify(
        payload: payload, signature: sign(payload), secret: secret, now: sent_at + 120
      )

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "accepts a payload at exactly the tolerance" do
      event = described_class.verify(
        payload: payload, signature: sign(payload), secret: secret, now: sent_at + 300
      )

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "honours a tolerance the caller widens" do
      event = described_class.verify(
        payload: payload, signature: sign(payload), secret: secret, tolerance: 86_400, now: sent_at + 3600
      )

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "can waive the freshness check" do
      event = described_class.verify(
        payload: payload, signature: sign(payload), secret: secret, tolerance: nil, now: sent_at + 2_592_000
      )

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "raises when the body carries no timestamp" do
      raw = { "event" => "ESCALATION_CREATED" }.to_json

      expect { described_class.verify(payload: raw, signature: sign(raw), secret: secret) }
        .to raise_error(Dregs::WebhookVerificationError, /no timestamp/)
    end

    it "accepts a body with no timestamp when the check is waived" do
      raw = { "event" => "ESCALATION_CREATED" }.to_json
      event = described_class.verify(payload: raw, signature: sign(raw), secret: secret, tolerance: nil)

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "raises on an unreadable timestamp" do
      raw = body("timestamp" => "the day before yesterday")

      expect { described_class.verify(payload: raw, signature: sign(raw), secret: secret) }
        .to raise_error(Dregs::WebhookVerificationError, /unreadable/)
    end

    it "defaults to now when the caller gives no reference time" do
      raw = body("timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
      event = described_class.verify(payload: raw, signature: sign(raw), secret: secret)

      expect(event["event"]).to eq("ESCALATION_CREATED")
    end

    it "does not mutate the reference time the caller passed" do
      moment = Time.new(2026, 9, 21, 16, 22, 9, "+02:00")

      described_class.verify(payload: payload, signature: sign(payload), secret: secret, now: moment)

      expect(moment.utc_offset).to eq(7200)
    end

    it "names the headers it expects" do
      expect(described_class::SIGNATURE_HEADER).to eq("X-Dregs-Signature")
      expect(described_class::TIMESTAMP_HEADER).to eq("X-Dregs-Timestamp")
      expect(described_class::EVENT_HEADER).to eq("X-Dregs-Event")
    end

    it "defaults the tolerance to five minutes" do
      expect(described_class::DEFAULT_TOLERANCE_SECONDS).to eq(300)
    end
  end
end
