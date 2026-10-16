# frozen_string_literal: true

require_relative "models"
require_relative "resource"

module Dregs
  # The +client.identities+ namespace: reading identities, their scores, and the reasoning behind
  # them, and the few writes that go with them.
  #
  # These methods are thin. They name the endpoint and hand the response to a model; the
  # transport, the retries, and the error mapping all live on {Client}.
  class Identities < Resource
    # Returns one page of identities, most recently updated first.
    #
    #   page = client.identities.list(term: "example.com", page_size: 50)
    #
    #   page.total_elements  #=> how many match in all
    #
    # Use {#list_all} to walk every page.
    #
    # @param term [String, nil] free text matched against ids, names, emails, and usernames
    # @param group [String, nil] only members of the group with this id. Pair it with
    #   +group_type:+ when your group ids are not unique across types.
    # @param group_type [String, nil] only members of groups of this type
    # @param device [String, nil] only identities seen on the device with this fingerprint
    # @param badge [String, nil] only identities carrying the badge with this slug
    # @param page [Integer] the page to return, counting from 0
    # @param page_size [Integer, nil] items per page, at most 100
    # @param sort [String, nil] the field to sort on, such as +"lastTrackedAt"+ or +"humanityScore"+
    # @param order [Symbol, String, nil] +:asc+ or +:desc+
    # @return [Page<Identity>]
    # @raise [ArgumentError] the page is negative or the order is not one of the two
    def list(term: nil, group: nil, group_type: nil, device: nil, badge: nil, page: 0, page_size: nil,
             sort: nil, order: nil)
      filters = list_filters(term: term, group: group, group_type: group_type, device: device, badge: badge)

      list_page("/identities", Identity, filters, page: page, page_size: page_size, sort: sort, order: order)
    end

    # Walks every identity that matches, fetching pages as it goes. Takes the filters {#list} does.
    #
    #   client.identities.list_all(group: "org_678").each do |identity|
    #     puts identity.display_email
    #   end
    #
    # @return [Enumerator<Identity>] a lazy enumerator, which fetches a page only when the items
    #   before it have been used up; nil when a block is given, which is called with each identity
    # @raise [ArgumentError] the order is not one of the two
    def list_all(term: nil, group: nil, group_type: nil, device: nil, badge: nil, page_size: nil, sort: nil,
                 order: nil, &block)
      filters = list_filters(term: term, group: group, group_type: group_type, device: device, badge: badge)

      list_every("/identities", Identity, filters, page_size: page_size, sort: sort, order: order, &block)
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

    # Returns an analysis cycle, with the observations behind each score.
    #
    # Use this when you need to show or log *why* an identity scored the way it did.
    #
    #   analysis = client.identities.analysis("user_12345")
    #   older = client.identities.analysis("user_12345", cycle_id: entry.cycle_id)
    #
    # @param identity_id [String] your own id for the user
    # @param cycle_id [Integer, nil] a past cycle to return, from {#history}; the most recent cycle
    #   when omitted
    # @return [Analysis]
    # @raise [NotFoundError] the identity is unknown, or it has not been analyzed yet
    def analysis(identity_id, cycle_id: nil)
      suffix = cycle_id.nil? ? "/analysis" : "/analysis/#{segment(cycle_id, "A cycle id")}"

      Analysis.from_api(@client.request(:get, path_for(identity_id, suffix)))
    end

    # Returns the scores of past analysis cycles, newest first.
    #
    #   client.identities.history("user_12345", limit: 10).each do |entry|
    #     puts "#{entry.finished_at} #{entry.humanity}"
    #   end
    #
    # @param identity_id [String] your own id for the user
    # @param limit [Integer, nil] the most cycles to return; the API's default is 100
    # @return [Array<ScoreHistoryEntry>]
    # @raise [NotFoundError] Dregs has never seen this identity
    def history(identity_id, limit: nil)
      payload = @client.request(:get, path_for(identity_id, "/history"), params: { "limit" => limit })

      parse_each(ScoreHistoryEntry, payload)
    end

    # Returns the other identities Dregs believes are connected to this one, such as by a shared
    # device.
    #
    # @param identity_id [String] your own id for the user
    # @return [Array<LinkedIdentity>]
    # @raise [NotFoundError] Dregs has never seen this identity
    def links(identity_id)
      parse_each(LinkedIdentity, @client.request(:get, path_for(identity_id, "/links")))
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

    # Updates an identity and returns it. Only what you pass is sent.
    #
    #   client.identities.update("qa_bot_7", disregarded: true)
    #
    # @param identity_id [String] your own id for the user
    # @param disregarded [Boolean, nil] true to leave the identity out of scoring and escalations,
    #   such as for your own staff or test accounts. Linked identities are re-scored.
    # @param attributes [Hash, nil] attributes to merge into the identity, as +identity_data:+ on
    #   {Client#track} would
    # @return [Identity]
    # @raise [NotFoundError] Dregs has never seen this identity
    # @raise [ArgumentError] neither +disregarded:+ nor +attributes:+ was given
    def update(identity_id, disregarded: nil, attributes: nil)
      body = {}

      body["disregarded"] = disregarded ? true : false unless disregarded.nil?
      body["attributes"] = attributes_hash(attributes) unless attributes.nil?

      raise ArgumentError, "Pass disregarded:, attributes:, or both." if body.empty?

      Identity.from_api(@client.request(:patch, path_for(identity_id), body: body))
    end

    # Returns the AI reviews requested for this identity, newest first.
    #
    # @param identity_id [String] your own id for the user
    # @return [Array<IdentityReview>]
    # @raise [NotFoundError] Dregs has never seen this identity
    def reviews(identity_id)
      parse_each(IdentityReview, @client.request(:get, path_for(identity_id, "/reviews")))
    end

    # Asks Dregs's AI reviewer to look over the identity's analysis.
    #
    # The review runs in the background, so the result comes back +"PENDING"+. Read it again with
    # {#reviews} once it has finished.
    #
    #   review = client.identities.review("user_12345", feedback: "This is a long-standing customer.")
    #
    #   review.status  #=> "PENDING"
    #
    # @param identity_id [String] your own id for the user
    # @param feedback [String, nil] what you think the analysis got wrong, such as "this is a real
    #   customer"
    # @return [IdentityReview]
    # @raise [NotFoundError] Dregs has never seen this identity
    def review(identity_id, feedback: nil)
      body = feedback.nil? || feedback.to_s.empty? ? {} : { "feedback" => feedback.to_s }

      IdentityReview.from_api(@client.request(:post, path_for(identity_id, "/actions/review"), body: body))
    end

    private

    def path_for(identity_id, suffix = "")
      "/identities/#{identity_segment(identity_id)}#{suffix}"
    end

    def list_filters(term:, group:, group_type:, device:, badge:)
      { "term" => term, "group" => group, "groupType" => group_type, "device" => device, "badge" => badge }
    end
  end
end
