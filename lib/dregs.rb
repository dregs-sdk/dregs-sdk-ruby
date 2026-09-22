# frozen_string_literal: true

require_relative "dregs/version"
require_relative "dregs/errors"
require_relative "dregs/models"
require_relative "dregs/identities"
require_relative "dregs/client"
require_relative "dregs/webhooks"

# Dregs: fraud and abuse scoring for the users of your application.
#
# Send events from your backend, read back the scores and the observations behind them.
#
#   require "dregs"
#
#   client = Dregs::Client.new
#
#   client.track(
#     "user.signup",
#     identity: "user_12345",
#     data: { plan: "pro" },
#     identity_data: { email: "ada@example.com" }
#   )
#
#   scores = client.identities.scores("user_12345")
#
#   hold_for_review("user_12345") if scores.authenticity && scores.authenticity < 40
#
# Scoring is asynchronous, so scores appear moments after the events that move them rather than in
# the same breath. See https://dregs.com/manual/api/ for the API this wraps.
module Dregs
  # Builds a {Client}. A convenience for +Dregs::Client.new+, which takes the same arguments.
  #
  # @return [Client]
  def self.new(**options)
    Client.new(**options)
  end
end
