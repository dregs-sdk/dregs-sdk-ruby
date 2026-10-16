# frozen_string_literal: true

RSpec.describe Dregs::Events do
  let(:client) { build_client }

  let(:event_payload) do
    {
      "id" => "signup-991",
      "timestamp" => "2026-10-15T10:00:00Z",
      "identity" => { "id" => "user_12345", "label" => "Ada", "path" => "/api/identities/user_12345" },
      "groups" => [
        { "type" => "team", "id" => "team_42", "label" => "Payments", "path" => "/api/groups/team/team_42" }
      ],
      "eventSource" => "ruby-sdk",
      "eventName" => "user.signup",
      "canonicalType" => "SIGNUP",
      "eventData" => { "plan" => "pro" }
    }
  end

  describe "#get" do
    it "parses the event, its identity, and its groups" do
      stub_json(:get, "/events/signup-991", event_payload)

      event = client.events.get("signup-991")

      expect(event.id).to eq("signup-991")
      expect(event.timestamp).to eq(Time.utc(2026, 10, 15, 10, 0, 0))
      expect(event.name).to eq("user.signup")
      expect(event.source).to eq("ruby-sdk")
      expect(event.canonical_type).to eq("SIGNUP")
      expect(event.data["plan"]).to eq("pro")
      expect(event.identity.id).to eq("user_12345")
      expect(event.identity.label).to eq("Ada")
      expect(event.groups.first.type).to eq("team")
      expect(event.groups.first.path).to eq("/api/groups/team/team_42")
    end

    it "leaves the identity nil and the groups empty when they are absent" do
      stub_json(:get, "/events/signup-991", { "id" => "signup-991" })

      event = client.events.get("signup-991")

      expect(event.identity).to be_nil
      expect(event.groups).to eq([])
      expect(event.data).to eq({})
    end

    it "refuses an empty id" do
      expect { client.events.get("") }.to raise_error(ArgumentError, /event id/)
    end
  end

  describe "#list" do
    it "sends the filters by their API names" do
      requests = capture_requests(:get, "/events", page_of([event_payload]))

      page = client.events.list(identity: "user_12345", group: "team_42", group_type: "team", session: "s1")

      expect(requests.last.uri.query_values).to include(
        "identity" => "user_12345", "group" => "team_42", "groupType" => "team", "session" => "s1"
      )
      expect(page.first.name).to eq("user.signup")
    end
  end
end
