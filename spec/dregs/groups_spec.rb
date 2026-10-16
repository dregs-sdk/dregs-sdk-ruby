# frozen_string_literal: true

RSpec.describe Dregs::Groups do
  let(:client) { build_client }

  let(:group_payload) do
    {
      "type" => "organization",
      "id" => "org_678",
      "displayName" => "Acme Inc",
      "identityCount" => 12,
      "createdAt" => "2026-10-01T10:00:00Z",
      "lastTrackedAt" => "2026-10-15T10:00:00Z",
      "data" => { "name" => "Acme Inc", "plan" => "enterprise" }
    }
  end

  describe "#list" do
    it "sends the group type as type" do
      requests = capture_requests(:get, "/groups", page_of([group_payload]))

      page = client.groups.list(group_type: "team", identity: "user_12345", term: "pay")

      expect(requests.last.uri.query_values).to include(
        "type" => "team", "identity" => "user_12345", "term" => "pay"
      )
      expect(page.first.id).to eq("org_678")
    end
  end

  describe "#get" do
    it "parses the group" do
      stub_json(:get, "/groups/organization/org_678", group_payload)

      group = client.groups.get("organization", "org_678")

      expect(group.type).to eq("organization")
      expect(group.display_name).to eq("Acme Inc")
      expect(group.identity_count).to eq(12)
      expect(group.data["plan"]).to eq("enterprise")
      expect(group.created_at).to eq(Time.utc(2026, 10, 1, 10, 0, 0))
      expect(group.updated_at).to be_nil
      expect(group.raw["displayName"]).to eq("Acme Inc")
    end

    it "escapes both segments" do
      stub_json(:get, "/groups/parent%20company/a%2Fb", group_payload)

      expect(client.groups.get("parent company", "a/b").id).to eq("org_678")
    end

    it "refuses a missing id before any request" do
      expect { client.groups.get("team", "") }.to raise_error(ArgumentError, /group id/)
      expect { client.groups.get(nil, "team_42") }.to raise_error(ArgumentError, /group type/)
    end
  end

  describe "#create" do
    it "defaults the type and sends the attributes" do
      requests = capture_requests(:post, "/groups", group_payload, status: 201)

      client.groups.create("org_678", attributes: { name: "Acme Inc" })

      expect(JSON.parse(requests.last.body)).to eq(
        "type" => "organization", "id" => "org_678", "attributes" => { "name" => "Acme Inc" }
      )
    end

    it "sends an empty object when there are no attributes" do
      requests = capture_requests(:post, "/groups", group_payload, status: 201)

      client.groups.create("team_42", group_type: "team")

      expect(JSON.parse(requests.last.body)).to eq("type" => "team", "id" => "team_42", "attributes" => {})
    end

    it "refuses a missing id before any request" do
      expect { client.groups.create("") }.to raise_error(ArgumentError, /group id/)
      expect(WebMock).not_to have_requested(:post, "#{BASE_URL}/groups")
    end
  end

  describe "#update" do
    it "sends the attributes to merge" do
      requests = capture_requests(:patch, "/groups/team/team_42", group_payload)

      client.groups.update("team", "team_42", { name: "Payments" })

      expect(JSON.parse(requests.last.body)).to eq("attributes" => { "name" => "Payments" })
    end
  end

  describe "membership" do
    let(:member_url) { "#{BASE_URL}/groups/team/team_42/identities/ada%40example.com" }

    it "adds and removes a member" do
      stub_request(:put, member_url).to_return(status: 204, body: "")
      stub_request(:delete, member_url).to_return(status: 204, body: "")

      expect(client.groups.add_member("team", "team_42", "ada@example.com")).to be_nil
      expect(client.groups.remove_member("team", "team_42", "ada@example.com")).to be_nil
      expect(WebMock).to have_requested(:put, member_url)
      expect(WebMock).to have_requested(:delete, member_url)
    end

    it "refuses a missing identity before any request" do
      expect { client.groups.add_member("team", "team_42", "") }.to raise_error(ArgumentError, /identity id/)
    end
  end
end
