# frozen_string_literal: true

RSpec.describe Dregs::Devices do
  let(:client) { build_client }

  let(:device_payload) do
    {
      "fingerprint" => "abc123",
      "ip" => "203.0.113.7",
      "asnLabel" => "Example Networks",
      "userAgent" => "Mozilla/5.0",
      "countryCode" => "US",
      "latitude" => 40.7,
      "disregarded" => false,
      "lastSeenAt" => "2026-10-15T10:00:00Z"
    }
  end

  describe "#get" do
    it "parses the device" do
      stub_json(:get, "/devices/abc123", device_payload)

      device = client.devices.get("abc123")

      expect(device.fingerprint).to eq("abc123")
      expect(device.asn_label).to eq("Example Networks")
      expect(device.user_agent).to eq("Mozilla/5.0")
      expect(device.country_code).to eq("US")
      expect(device.latitude).to eq(40.7)
      expect(device.disregarded?).to be(false)
      expect(device.last_seen_at).to eq(Time.utc(2026, 10, 15, 10, 0, 0))
    end
  end

  describe "#update" do
    it "sends the disregarded flag" do
      requests = capture_requests(:patch, "/devices/abc123", device_payload.merge("disregarded" => true))

      device = client.devices.update("abc123", disregarded: true)

      expect(JSON.parse(requests.last.body)).to eq("disregarded" => true)
      expect(device.disregarded?).to be(true)
    end
  end

  describe "#list" do
    it "sends the filters" do
      requests = capture_requests(:get, "/devices", page_of([device_payload]))

      client.devices.list(identity: "user_12345", term: "Chrome")

      expect(requests.last.uri.query_values).to include("identity" => "user_12345", "term" => "Chrome")
    end
  end
end
