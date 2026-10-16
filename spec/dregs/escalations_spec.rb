# frozen_string_literal: true

RSpec.describe Dregs::Escalations do
  let(:client) { build_client }

  let(:escalation_payload) do
    {
      "id" => 41,
      "status" => "ACKNOWLEDGED",
      "severity" => "WARNING",
      "identity" => { "id" => "user_12345" },
      "escalationRule" => { "id" => "3", "label" => "Low humanity" },
      "scoreSnapshot" => { "humanity" => 12 },
      "openedAt" => "2026-10-15T10:00:00Z"
    }
  end

  describe "#list" do
    it "upper-cases the status and the severity" do
      requests = capture_requests(:get, "/escalations", page_of([escalation_payload]))

      client.escalations.list(status: :open, severity: "critical", rule: 3)

      expect(requests.last.uri.query_values).to include(
        "status" => "OPEN", "severity" => "CRITICAL", "rule" => "3"
      )
    end

    it "refuses an unknown status before any request" do
      expect { client.escalations.list(status: "snoozed") }.to raise_error(ArgumentError, /acknowledged/)
      expect(WebMock).not_to have_requested(:get, /escalations/)
    end
  end

  describe "#get" do
    it "parses the escalation" do
      stub_json(:get, "/escalations/41", escalation_payload)

      escalation = client.escalations.get(41)

      expect(escalation.id).to eq(41)
      expect(escalation.severity).to eq("WARNING")
      expect(escalation.identity.id).to eq("user_12345")
      expect(escalation.rule.label).to eq("Low humanity")
      expect(escalation.scores["humanity"]).to eq(12)
      expect(escalation.opened_at).to eq(Time.utc(2026, 10, 15, 10, 0, 0))
      expect(escalation.closed_at).to be_nil
    end
  end

  describe "#update" do
    it "sends the status upper-cased" do
      requests = capture_requests(:patch, "/escalations/41", escalation_payload)

      escalation = client.escalations.update(41, status: "acknowledged")

      expect(JSON.parse(requests.last.body)).to eq("status" => "ACKNOWLEDGED")
      expect(escalation.status).to eq("ACKNOWLEDGED")
    end

    it "refuses an unknown status before any request" do
      expect { client.escalations.update(41, status: :snoozed) }.to raise_error(ArgumentError, /acknowledged/)
      expect(WebMock).not_to have_requested(:patch, /escalations/)
    end
  end

  describe "#summary" do
    it "parses the counts" do
      stub_json(:get, "/escalations/summary", { "open" => 3, "acknowledged" => 1, "closed" => 20 })

      summary = client.escalations.summary

      expect([summary.open, summary.acknowledged, summary.closed]).to eq([3, 1, 20])
    end

    it "reads a missing count as zero" do
      stub_json(:get, "/escalations/summary", {})

      expect(client.escalations.summary.open).to eq(0)
    end
  end
end
