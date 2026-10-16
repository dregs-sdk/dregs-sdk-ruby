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

  # Stubs any endpoint, whatever its query string, and returns the array its requests are collected
  # into. Each request is answered with the next of +responses+, and the last one repeats.
  def capture_requests(method, path, *responses, status: 200)
    requests = []
    pattern = /\A#{Regexp.escape("#{BASE_URL}#{path}")}(\?.*)?\z/

    stub_request(method, pattern).to_return do |request|
      response = responses[[requests.size, responses.size - 1].min]
      requests << request

      {
        status: status,
        body: response.nil? ? "" : response.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end

    requests
  end

  # Builds the API's +V1Page+ around +content+.
  def page_of(content, number: 0, last: true, total: nil)
    {
      "pageNumber" => number,
      "pageSize" => 2,
      "totalPages" => last ? number + 1 : number + 2,
      "totalElements" => total || content.size,
      "content" => content,
      "first" => number.zero?,
      "last" => last,
      "numberOfElements" => content.size
    }
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
