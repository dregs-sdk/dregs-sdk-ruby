# frozen_string_literal: true

RSpec.describe Dregs::Identities do
  let(:client) { build_client }

  let(:identity_payload) do
    {
      "id" => "user_12345",
      "displayName" => "Ada Lovelace",
      "displayEmail" => "ada@example.com",
      "displayUsername" => "ada",
      "humanityScore" => 85,
      "authenticityScore" => 72,
      "uniquenessScore" => 91,
      "behaviorScore" => 68,
      "createdAt" => "2026-09-01T10:00:00Z",
      "lastTrackedAt" => "2026-09-21T14:20:00Z",
      "disregarded" => false,
      "badges" => [
        {
          "slug" => "behavior.account-takeover-signal",
          "name" => "Account Takeover Suspected",
          "type" => "ANALYZER",
          "explanation" => "Credential move from a new device",
          "metadata" => { "devices" => 2 }
        }
      ],
      "data" => { "email" => "ada@example.com", "plan" => "pro" }
    }
  end

  let(:analysis_payload) do
    {
      "id" => 2_000_871,
      "identityId" => "user_12345",
      "scores" => [
        {
          "category" => "HUMANITY",
          "value" => 85,
          "observations" => [
            {
              "category" => "HUMANITY",
              "id" => "humanity.user-agent",
              "label" => "User Agent Analysis",
              "explanation" => "Browser fingerprint consistent with standard Chrome on macOS",
              "value" => 0.92,
              "confidence" => 0.85,
              "weight" => 0.85,
              "metadata" => { "browser" => "Chrome" }
            }
          ]
        },
        { "category" => "BEHAVIOR", "value" => 68, "observations" => [] }
      ],
      "eventCount" => 47,
      "deviceCount" => 2,
      "durationMillis" => 312,
      "startedAt" => "2026-09-21T14:22:09Z",
      "finishedAt" => "2026-09-21T14:22:09Z"
    }
  end

  describe "#get" do
    before { stub_json(:get, "/identities/user_12345", identity_payload) }

    it "parses the identity" do
      identity = client.identities.get("user_12345")

      expect(identity.id).to eq("user_12345")
      expect(identity.display_email).to eq("ada@example.com")
      expect(identity.display_username).to eq("ada")
      expect(identity.humanity_score).to eq(85)
    end

    it "parses timestamps as UTC times" do
      identity = client.identities.get("user_12345")

      expect(identity.created_at).to eq(Time.utc(2026, 9, 1, 10, 0, 0))
      expect(identity.last_tracked_at).to eq(Time.utc(2026, 9, 21, 14, 20, 0))
    end

    it "leaves an absent timestamp nil" do
      expect(client.identities.get("user_12345").last_scored_at).to be_nil
    end

    it "parses the attributes you have sent" do
      expect(client.identities.get("user_12345").data["plan"]).to eq("pro")
    end

    it "reports the disregarded flag both ways" do
      identity = client.identities.get("user_12345")

      expect(identity.disregarded).to be(false)
      expect(identity.disregarded?).to be(false)
    end

    it "parses badges" do
      badge = client.identities.get("user_12345").badges.first

      expect(badge.name).to eq("Account Takeover Suspected")
      expect(badge.slug).to eq("behavior.account-takeover-signal")
      expect(badge.metadata["devices"]).to eq(2)
    end

    it "exposes the same scores view as the scores call" do
      scores = client.identities.get("user_12345").scores

      expect(scores.humanity).to eq(85)
      expect(scores.behavior).to eq(68)
      expect(scores.size).to eq(4)
    end
  end

  describe "path escaping" do
    it "escapes an identity id that needs it" do
      stub_json(:get, "/identities/ada%40example.com", { "id" => "ada@example.com" })

      expect(client.identities.get("ada@example.com").id).to eq("ada@example.com")
    end

    it "escapes a space rather than sending a plus" do
      stub_json(:get, "/identities/ada%20lovelace", { "id" => "ada lovelace" })

      expect(client.identities.get("ada lovelace").id).to eq("ada lovelace")
    end

    it "escapes a slash so it cannot change the route" do
      stub_json(:get, "/identities/a%2Fb", { "id" => "a/b" })

      expect(client.identities.get("a/b").id).to eq("a/b")
    end

    it "refuses an empty identity id" do
      expect { client.identities.get("") }.to raise_error(ArgumentError, /identity id is required/)
    end
  end

  describe "#scores" do
    it "exposes each category by name" do
      stub_json(:get, "/identities/user_12345/scores", [
                  { "category" => "HUMANITY", "value" => 85 },
                  { "category" => "AUTHENTICITY", "value" => 72 },
                  { "category" => "UNIQUENESS", "value" => 91 },
                  { "category" => "BEHAVIOR", "value" => 68 }
                ])

      scores = client.identities.scores("user_12345")

      expect(scores.humanity).to eq(85)
      expect(scores.authenticity).to eq(72)
      expect(scores.uniqueness).to eq(91)
      expect(scores.behavior).to eq(68)
    end

    it "is enumerable" do
      stub_json(:get, "/identities/user_12345/scores", [
                  { "category" => "HUMANITY", "value" => 85 },
                  { "category" => "BEHAVIOR", "value" => 68 }
                ])

      scores = client.identities.scores("user_12345")

      expect(scores).to be_a(Enumerable)
      expect(scores.map(&:category)).to eq(%i[humanity behavior])
      expect(scores.map(&:value).sum).to eq(153)
      expect(scores.size).to eq(2)
      expect(scores[0].value).to eq(85)
    end

    it "finds a score by category" do
      stub_json(:get, "/identities/user_12345/scores", [{ "category" => "HUMANITY", "value" => 85 }])

      scores = client.identities.scores("user_12345")

      expect(scores.get(Dregs::Category::HUMANITY).value).to eq(85)
      expect(scores.get(Dregs::Category::BEHAVIOR)).to be_nil
    end

    it "reads an unscored category as nil" do
      stub_json(:get, "/identities/user_12345/scores", [{ "category" => "HUMANITY", "value" => 85 }])

      scores = client.identities.scores("user_12345")

      expect(scores.humanity).to eq(85)
      expect(scores.behavior).to be_nil
    end

    it "comes back empty for an identity with no scores yet" do
      stub_json(:get, "/identities/user_12345/scores", [])

      scores = client.identities.scores("user_12345")

      expect(scores).to be_empty
      expect(scores.humanity).to be_nil
    end

    it "carries no observations" do
      stub_json(:get, "/identities/user_12345/scores", [{ "category" => "HUMANITY", "value" => 85 }])

      expect(client.identities.scores("user_12345").first.observations).to eq([])
    end
  end

  describe "#analysis" do
    before { stub_json(:get, "/identities/user_12345/analysis", analysis_payload) }

    it "parses the cycle" do
      analysis = client.identities.analysis("user_12345")

      expect(analysis.id).to eq(2_000_871)
      expect(analysis.identity_id).to eq("user_12345")
      expect(analysis.event_count).to eq(47)
      expect(analysis.device_count).to eq(2)
      expect(analysis.duration_millis).to eq(312)
      expect(analysis.finished_at).to eq(Time.utc(2026, 9, 21, 14, 22, 9))
    end

    it "parses the scores it carries" do
      expect(client.identities.analysis("user_12345").scores.humanity).to eq(85)
    end

    it "parses the observations behind a score" do
      observation = client.identities.analysis("user_12345").scores.first.observations.first

      expect(observation.id).to eq("humanity.user-agent")
      expect(observation.label).to eq("User Agent Analysis")
      expect(observation.value).to eq(0.92)
      expect(observation.confidence).to eq(0.85)
      expect(observation.weight).to eq(0.85)
      expect(observation.metadata["browser"]).to eq("Chrome")
      expect(observation.category).to eq(Dregs::Category::HUMANITY)
    end

    it "flattens observations across categories" do
      analysis = client.identities.analysis("user_12345")

      expect(analysis.observations.size).to eq(1)
      expect(analysis.observations.first.category).to eq(:humanity)
    end
  end

  describe "#analyze" do
    let(:analyze_url) { "#{BASE_URL}/identities/user_12345/actions/analyze" }

    it "posts to the action endpoint" do
      stub_request(:post, analyze_url).to_return(status: 201, body: "")

      expect(client.identities.analyze("user_12345")).to be_nil
      expect(WebMock).to have_requested(:post, analyze_url)
    end

    it "raises when the identity is unknown" do
      stub_request(:post, "#{BASE_URL}/identities/nobody/actions/analyze").to_return(status: 404, body: "")

      expect { client.identities.analyze("nobody") }.to raise_error(Dregs::NotFoundError)
    end
  end

  describe "lenient parsing" do
    it "keeps an unknown field on raw" do
      stub_json(:get, "/identities/user_12345", { "id" => "user_12345", "somethingNew" => 42 })

      expect(client.identities.get("user_12345").raw["somethingNew"]).to eq(42)
    end

    it "leaves a missing field nil rather than raising" do
      stub_json(:get, "/identities/user_12345", { "id" => "user_12345" })

      identity = client.identities.get("user_12345")

      expect(identity.display_name).to be_nil
      expect(identity.humanity_score).to be_nil
      expect(identity.badges).to eq([])
      expect(identity.data).to eq({})
    end

    it "ignores an unreadable timestamp" do
      stub_json(:get, "/identities/user_12345", { "id" => "user_12345", "createdAt" => "the other day" })

      expect(client.identities.get("user_12345").created_at).to be_nil
    end

    it "does not break on a category this release predates" do
      stub_json(:get, "/identities/user_12345/scores", [
                  { "category" => "REPUTATION", "value" => 50 },
                  { "category" => "HUMANITY", "value" => 85 }
                ])

      scores = client.identities.scores("user_12345")

      expect(scores.size).to eq(2)
      expect(scores.humanity).to eq(85)
      expect(scores.first.category).to be_nil
      expect(scores.first.raw["category"]).to eq("REPUTATION")
    end

    it "tolerates a response that is not the shape it expected" do
      stub_json(:get, "/identities/user_12345/scores", { "unexpected" => true })

      expect(client.identities.scores("user_12345")).to be_empty
    end
  end
end
