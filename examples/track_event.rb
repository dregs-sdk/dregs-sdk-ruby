#!/usr/bin/env ruby
# frozen_string_literal: true

# Send a backend event to Dregs.
#
# Run it with your credential's secret key in the environment:
#
#     DREGS_SECRET_KEY=sk_... bundle exec ruby examples/track_event.rb

require "dregs"

client = Dregs::Client.new

begin
  result = client.track(
    "user.signup",
    identity: "user_12345",
    # Attributes of the event.
    data: { plan: "pro", referrer: "partner-x" },
    # Attributes of the user. The analyzers lean on these, so send what you have.
    identity_data: { email: "ada@example.com", name: "Ada Lovelace", username: "ada" },
    # Your own id for the event makes ingestion idempotent: resending this exact call is a no-op
    # rather than a second signup.
    event_id: "signup-991"
  )
rescue Dregs::QuotaExceededError
  abort "Over the monthly event limit. The event was not recorded."
rescue Dregs::RateLimitError => e
  abort "Rate limited. Retry after #{e.retry_after || "a moment"}."
rescue Dregs::Error => e
  abort "Could not reach Dregs: #{e.message}"
end

if result.accepted?
  puts "Recorded event #{result.id}."
else
  # Uncommon, and worth a log line: accepted without an event being recorded.
  puts "The event was not recorded (status #{result.status})."
end
