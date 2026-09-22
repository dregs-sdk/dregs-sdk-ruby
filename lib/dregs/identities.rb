# frozen_string_literal: true

require "uri"

require_relative "models"

module Dregs
  # The +client.identities+ namespace: reading identities, their scores, and the reasoning behind
  # them.
  #
  # These methods are thin. They name the endpoint and hand the response to a model; the
  # transport, the retries, and the error mapping all live on {Client}.
  class Identities
    # @api private
    # @param client [Client]
    def initialize(client)
      @client = client
    end

    # Returns the identity, with its current scores, badges, and attributes.
    #
    #   identity = client.identities.get("user_12345")
    #
    #   identity.display_email  #=> "ada@example.com"
    #   identity.badges.map(&:name)
    #
    # @param identity_id [String] your own id for the user. It is escaped for you, so an email
    #   address or anything else with awkward characters in it works as-is.
    # @return [Identity]
    # @raise [NotFoundError] Dregs has never seen this identity
    def get(identity_id)
      Identity.from_api(@client.request(:get, path_for(identity_id)))
    end

    # Returns the current category scores.
    #
    # This is the cheap read and the one most integrations want. It reports the scores Dregs has
    # already computed without triggering any work. For the observations behind them, use
    # {#analysis}.
    #
    # A category that has not been scored yet is absent, so a brand-new identity comes back empty.
    #
    # @param identity_id [String] your own id for the user
    # @return [Scores]
    # @raise [NotFoundError] Dregs has never seen this identity
    def scores(identity_id)
      Scores.from_api(@client.request(:get, path_for(identity_id, "/scores")))
    end

    # Returns the most recent analysis cycle, with the observations behind each score.
    #
    # Use this when you need to show or log *why* an identity scored the way it did.
    #
    # @param identity_id [String] your own id for the user
    # @return [Analysis]
    # @raise [NotFoundError] the identity is unknown, or it has not been analyzed yet
    def analysis(identity_id)
      Analysis.from_api(@client.request(:get, path_for(identity_id, "/analysis")))
    end

    # Queues a re-analysis of the identity.
    #
    # Scoring is asynchronous: this returns as soon as the job is queued, not when it has run.
    # Poll {#scores} or watch for a webhook rather than expecting fresh scores on the next line.
    # Dregs rescores on its own as events arrive, so you rarely need this outside a support or
    # backfill flow.
    #
    # @param identity_id [String] your own id for the user
    # @return [nil]
    # @raise [NotFoundError] Dregs has never seen this identity
    def analyze(identity_id)
      @client.request(:post, path_for(identity_id, "/actions/analyze"))

      nil
    end

    private

    def path_for(identity_id, suffix = "")
      raise ArgumentError, "An identity id is required." if identity_id.nil? || identity_id.to_s.empty?

      # Identity ids are the caller's own user ids and routinely contain characters that need
      # escaping, an email address being the common one.
      "/identities/#{escape(identity_id.to_s)}#{suffix}"
    end

    def escape(value)
      URI.encode_www_form_component(value).gsub("+", "%20")
    end
  end
end
