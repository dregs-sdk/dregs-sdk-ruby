# frozen_string_literal: true

RSpec.describe Dregs::Client do
  let(:client) { build_client }

  describe "construction" do
    it "reads the secret key from the environment" do
      ENV["DREGS_SECRET_KEY"] = SECRET_KEY

      expect(described_class.new.base_url).to eq("https://dregs.com/api")
    end

    it "reads the base url from the environment" do
      ENV["DREGS_BASE_URL"] = "https://staging.example.com/api"

      expect(described_class.new(secret_key: SECRET_KEY).base_url).to eq("https://staging.example.com/api")
    end

    it "prefers an explicit base url over the environment" do
      ENV["DREGS_BASE_URL"] = "https://staging.example.com/api"

      expect(described_class.new(secret_key: SECRET_KEY, base_url: BASE_URL).base_url).to eq(BASE_URL)
    end

    it "does not double up a trailing slash on the base url" do
      expect(described_class.new(secret_key: SECRET_KEY, base_url: "#{BASE_URL}/").base_url).to eq(BASE_URL)
    end

    it "names the environment variable when no key is available" do
      expect { described_class.new }.to raise_error(ArgumentError, /DREGS_SECRET_KEY/)
    end

    it "refuses a public key with an explanation" do
      expect { described_class.new(secret_key: "pk_abcdefghQijklmQabcdefghijklmn") }
        .to raise_error(ArgumentError, /public key/)
    end

    it "refuses a negative retry count" do
      expect { described_class.new(secret_key: SECRET_KEY, max_retries: -1) }
        .to raise_error(ArgumentError, /max_retries/)
    end

    it "defaults to two retries" do
      expect(described_class.new(secret_key: SECRET_KEY).max_retries).to eq(2)
    end

    it "exposes the identities namespace" do
      expect(client.identities).to be_a(Dregs::Identities)
    end

    it "exposes the groups, events, devices, and escalations namespaces" do
      expect(client.groups).to be_a(Dregs::Groups)
      expect(client.events).to be_a(Dregs::Events)
      expect(client.devices).to be_a(Dregs::Devices)
      expect(client.escalations).to be_a(Dregs::Escalations)
    end

    it "can also be built through Dregs.new" do
      expect(Dregs.new(secret_key: SECRET_KEY)).to be_a(described_class)
    end
  end

  describe "#track request" do
    it "sends the documented body" do
      bodies = capture_events

      client.track(
        "user.signup",
        identity: "user_12345",
        data: { "plan" => "pro" },
        identity_data: { "email" => "ada@example.com" },
        event_id: "signup-991"
      )

      expect(bodies.last).to eq(
        "id" => "signup-991",
        "type" => "user.signup",
        "data" => { "plan" => "pro" },
        "identity" => { "id" => "user_12345", "data" => { "email" => "ada@example.com" } },
        "source" => "ruby-sdk"
      )
    end

    it "sends empty maps when the caller has no attributes" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345")

      expect(bodies.last["data"]).to eq({})
      expect(bodies.last["identity"]).to eq("id" => "user_12345", "data" => {})
    end

    it "authorizes with the secret key" do
      capture_events

      client.track("user.signup", identity: "user_12345")

      expect(WebMock).to have_requested(:post, "#{BASE_URL}/events")
        .with(headers: { "Authorization" => "Bearer #{SECRET_KEY}" })
    end

    it "identifies itself in the user agent" do
      capture_events

      client.track("user.signup", identity: "user_12345")

      expect(WebMock).to have_requested(:post, "#{BASE_URL}/events")
        .with(headers: { "User-Agent" => %r{\Adregs-ruby/#{Regexp.escape(Dregs::VERSION)} \(ruby } })
    end

    it "sends JSON" do
      capture_events

      client.track("user.signup", identity: "user_12345")

      expect(WebMock).to have_requested(:post, "#{BASE_URL}/events")
        .with(headers: { "Content-Type" => "application/json" })
    end

    it "lets the caller override the source" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345", source: "billing-worker")

      expect(bodies.last["source"]).to eq("billing-worker")
    end

    it "generates a fresh event id for each call" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345")
      client.track("user.signup", identity: "user_12345")

      expect(bodies.map { |body| body["id"] }.uniq.size).to eq(2)
    end

    it "generates an event id the API will accept" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345")

      id = bodies.last["id"]

      expect(id).not_to start_with("dregs-")
      expect(id.length).to be_between(1, 64)
    end

    it "sends a Time as UTC" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345", timestamp: Time.utc(2026, 9, 21, 14, 22, 9))

      expect(bodies.last["timestamp"]).to eq("2026-09-21T14:22:09Z")
    end

    it "converts a zoned Time to UTC without mutating it" do
      bodies = capture_events
      moment = Time.new(2026, 9, 21, 16, 22, 9, "+02:00")

      client.track("user.signup", identity: "user_12345", timestamp: moment)

      expect(bodies.last["timestamp"]).to eq("2026-09-21T14:22:09Z")
      expect(moment.utc_offset).to eq(7200)
    end

    it "passes an ISO-8601 string through" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345", timestamp: "2026-09-21T14:22:09Z")

      expect(bodies.last["timestamp"]).to eq("2026-09-21T14:22:09Z")
    end

    it "omits the timestamp when the caller does" do
      bodies = capture_events

      client.track("user.signup", identity: "user_12345")

      expect(bodies.last).not_to have_key("timestamp")
    end

    it "refuses an empty identity before any request" do
      expect { client.track("user.signup", identity: "") }
        .to raise_error(ArgumentError, /identity is required/)
    end

    it "refuses an empty event type" do
      expect { client.track("", identity: "user_12345") }
        .to raise_error(ArgumentError, /event_type is required/)
    end

    it "refuses a reserved event id" do
      expect { client.track("user.signup", identity: "user_12345", event_id: "dregs-1234") }
        .to raise_error(ArgumentError, /reserved/)
    end

    it "refuses an overlong event id" do
      expect { client.track("user.signup", identity: "user_12345", event_id: "x" * 65) }
        .to raise_error(ArgumentError, /64 characters/)
    end

    it "sends the groups" do
      bodies = capture_events

      client.track(
        "user.login",
        identity: "user_12345",
        groups: [
          { type: "organization", id: "org_678", data: { name: "Acme Inc" } },
          { "type" => "team", "id" => 42 }
        ]
      )

      expect(bodies.last["groups"]).to eq(
        [
          { "type" => "organization", "id" => "org_678", "data" => { "name" => "Acme Inc" } },
          { "type" => "team", "id" => "42", "data" => {} }
        ]
      )
    end

    it "treats a group without a type as an organization" do
      bodies = capture_events

      client.track("user.login", identity: "user_12345", groups: [{ id: "org_678" }])

      expect(bodies.last["groups"]).to eq([{ "type" => "organization", "id" => "org_678", "data" => {} }])
    end

    it "omits the groups when there are none" do
      bodies = capture_events

      client.track("user.login", identity: "user_12345")
      client.track("user.login", identity: "user_12345", groups: [])

      expect(bodies[0]).not_to have_key("groups")
      expect(bodies[1]).not_to have_key("groups")
    end

    {
      "a hash instead of an array" => [{ type: "team", id: "team_42" }, /array of groups/],
      "an entry that is not a hash" => [["team_42"], /must be a hash/],
      "a group without an id" => [[{ type: "team" }], /needs an id/],
      "a group with an empty id" => [[{ type: "team", id: "" }], /needs an id/],
      "a type that is not a string" => [[{ type: 7, id: "team_42" }], /must be a string/],
      "two groups of one type" => [
        [{ type: "team", id: "a" }, { type: "Team", id: "b" }],
        /one group of each type/
      ],
      "an untyped group beside an organization" => [
        [{ id: "a" }, { type: "organization", id: "b" }],
        /one group of each type/
      ],
      "data that is not a hash" => [[{ type: "team", id: "a", data: ["x"] }], /data must be a hash/]
    }.each do |description, (groups, message)|
      it "refuses #{description} before any request" do
        capture_events

        expect { client.track("user.login", identity: "user_12345", groups: groups) }
          .to raise_error(ArgumentError, message)
        expect(WebMock).not_to have_requested(:post, "#{BASE_URL}/events")
      end
    end

    it "does not reach the network when an argument is refused" do
      capture_events

      expect { client.track("user.signup", identity: nil) }.to raise_error(ArgumentError)
      expect(WebMock).not_to have_requested(:post, "#{BASE_URL}/events")
    end
  end

  describe "#track response" do
    it "reports an accepted event" do
      capture_events({ "status" => "success", "id" => "evt_1", "fingerprint" => nil })

      result = client.track("user.signup", identity: "user_12345")

      expect(result.accepted?).to be(true)
      expect(result.id).to eq("evt_1")
      expect(result.status).to eq("success")
    end

    it "keeps the raw body for fields this release does not know" do
      capture_events({ "status" => "success", "id" => "evt_1", "somethingNew" => 42 })

      expect(client.track("user.signup", identity: "user_12345").raw["somethingNew"]).to eq(42)
    end

    it "does not treat a quiet rejection as accepted" do
      capture_events({ "status" => "success", "id" => nil, "fingerprint" => nil })

      result = client.track("user.signup", identity: "user_12345")

      expect(result.accepted?).to be(false)
      expect(result.id).to be_nil
    end

    it "tolerates an empty body" do
      stub_request(:post, "#{BASE_URL}/events").to_return(status: 200, body: "")

      expect(client.track("user.signup", identity: "user_12345").accepted?).to be(false)
    end
  end
end
