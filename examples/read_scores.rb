#!/usr/bin/env ruby
# frozen_string_literal: true

# Read an identity's scores, and the observations behind them.
#
#     DREGS_SECRET_KEY=sk_... bundle exec ruby examples/read_scores.rb user_12345

require "dregs"

identity_id = ARGV.fetch(0, "user_12345")
client = Dregs::Client.new

def format_score(score)
  score.nil? ? "not scored" : score.to_s
end

begin
  scores = client.identities.scores(identity_id)
rescue Dregs::NotFoundError
  abort "Dregs has never seen #{identity_id}."
end

if scores.empty?
  abort "#{identity_id} has not been scored yet. Scoring runs shortly after new activity."
end

puts "Scores for #{identity_id}"
puts "  Humanity:     #{format_score(scores.humanity)}"
puts "  Authenticity: #{format_score(scores.authenticity)}"
puts "  Uniqueness:   #{format_score(scores.uniqueness)}"
puts "  Behavior:     #{format_score(scores.behavior)}"

# The scores are the summary. The observations are the evidence, and they come from the analysis
# cycle rather than from the scores endpoint.
begin
  analysis = client.identities.analysis(identity_id)
rescue Dregs::NotFoundError
  abort "\nNo analysis cycle has finished for this identity yet."
end

puts "\nWhy, from the cycle of #{analysis.finished_at&.strftime("%Y-%m-%d %H:%M")} UTC:"

analysis.observations.sort_by { |observation| observation.value || 1.0 }.each do |observation|
  puts "  [#{observation.category}] #{observation.label}"
  puts "      #{observation.explanation}"
  puts "      value #{observation.value}, confidence #{observation.confidence}"
end
