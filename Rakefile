# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc "Validate the RBS signatures"
task :rbs do
  sh "bundle exec rbs -I sig validate --silent"
end

task default: %i[rubocop rbs spec]
