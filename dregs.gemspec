# frozen_string_literal: true

require_relative "lib/dregs/version"

Gem::Specification.new do |spec|
  spec.name = "dregs"
  spec.version = Dregs::VERSION
  spec.authors = ["Dregs"]
  spec.email = ["support@dregs.com"]

  spec.summary = "Ruby SDK for Dregs, the fraud and abuse scoring service."
  spec.description = <<~DESCRIPTION
    The official Ruby client for Dregs, which scores the users of your application for fraud and
    abuse across four categories: humanity, authenticity, uniqueness, and behavior. Send events
    from your backend, read back the scores and the observations behind them.
  DESCRIPTION
  spec.homepage = "https://dregs.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata = {
    "homepage_uri" => "https://dregs.com",
    "documentation_uri" => "https://dregs.com/manual/api/",
    "source_code_uri" => "https://github.com/dregs-sdk/dregs-sdk-ruby",
    "bug_tracker_uri" => "https://github.com/dregs-sdk/dregs-sdk-ruby/issues",
    "changelog_uri" => "https://github.com/dregs-sdk/dregs-sdk-ruby/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "SECURITY.md"
  ]
  spec.require_paths = ["lib"]

  # No runtime dependencies, deliberately. Everything this gem needs is in the standard library,
  # so adding it to an application cannot conflict with the HTTP or JSON gems already there.
end
