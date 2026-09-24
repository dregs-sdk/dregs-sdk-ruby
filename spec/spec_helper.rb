# frozen_string_literal: true

require "json"
require "webmock/rspec"

require "dregs"

# Every spec talks to this host, which WebMock intercepts. Nothing in the suite touches the
# network; WebMock raises if anything tries.
BASE_URL = "https://api.test.invalid/api"
SECRET_KEY = "sk_abcdefghQijklmQabcdefghijklmn"
ACCEPTED_EVENT = { "status" => "success", "id" => "evt_1" }.freeze

# Helpers available to every example.
module SpecHelpers
  # Builds a client whose retry backoff does not actually wait, so the retry specs run instantly.
  def build_client(max_retries: 0, **options)
    client = Dregs::Client.new(
      secret_key: SECRET_KEY,
      base_url: BASE_URL,
      max_retries: max_retries,
      **options
    )

    allow(client).to receive(:backoff).and_return(0)

    client
  end

  # Stubs +POST /api/events+ and returns the array the request bodies are collected into, so a
  # spec can assert on what was actually sent rather than on a matcher's opinion of it.
  def capture_events(response = ACCEPTED_EVENT, status: 200)
    bodies = []

    stub_request(:post, "#{BASE_URL}/events").to_return do |request|
      bodies << JSON.parse(request.body)

      { status: status, body: response.to_json, headers: { "Content-Type" => "application/json" } }
    end

    bodies
  end

  # Stubs a JSON response for any endpoint.
  def stub_json(method, path, body, status: 200, headers: {})
    stub_request(method, "#{BASE_URL}#{path}").to_return(
      status: status,
      body: body.nil? ? "" : body.to_json,
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end
end

RSpec.configure do |config|
  config.include SpecHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random

  Kernel.srand config.seed

  # Keeps a developer's own DREGS_* variables out of the suite, and puts them back afterwards.
  config.around do |example|
    saved = ENV.to_h.select { |name, _| name.start_with?("DREGS_") }

    saved.each_key { |name| ENV.delete(name) }

    example.run

    ENV.to_h.each_key { |name| ENV.delete(name) if name.start_with?("DREGS_") }

    saved.each { |name, value| ENV[name] = value }
  end
end
