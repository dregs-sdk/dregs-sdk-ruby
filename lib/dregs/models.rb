# frozen_string_literal: true

require "time"

module Dregs
  # The four categories Dregs scores an identity in.
  #
  # The API spells them in upper case (+"HUMANITY"+); this SDK hands you lower-case symbols
  # (+:humanity+) and keeps the string Dregs sent in the model's +raw+. A category this release
  # predates parses as +nil+ rather than raising, so a future fifth category cannot break an
  # otherwise good response.
  module Category
    HUMANITY = :humanity
    AUTHENTICITY = :authenticity
    UNIQUENESS = :uniqueness
    BEHAVIOR = :behavior

    # Every category, in the order the dashboard shows them.
    ALL = [HUMANITY, AUTHENTICITY, UNIQUENESS, BEHAVIOR].freeze

    # Turns the API's spelling of a category into a symbol.
    #
    # @param value [String, Symbol, nil] the +category+ field from a response
    # @return [Symbol, nil] the matching category, or nil when it is not one this release knows
    def self.parse(value)
      return nil unless value.is_a?(String) || value.is_a?(Symbol)

      symbol = value.to_s.downcase.to_sym

      ALL.include?(symbol) ? symbol : nil
    end
  end

  # Parsing helpers shared by the models.
  #
  # Parsing is deliberately lenient: a missing field becomes +nil+ rather than an error, because an
  # SDK that refuses to parse a response it half-understands is worse than one that hands back what
  # it got.
  #
  # @api private
  module Parsing
    module_function

    # @param value [Object] an ISO-8601 string, or anything else
    # @return [Time, nil] the parsed time in UTC, or nil when it was unreadable
    def time(value)
      return nil unless value.is_a?(String) && !value.empty?

      begin
        Time.iso8601(value).getutc
      rescue ArgumentError
        nil
      end
    end

    # @param value [Object]
    # @return [Hash] the value when it is a hash, otherwise an empty hash
    def hash_or_empty(value)
      value.is_a?(Hash) ? value : {}
    end

    # @param value [Object]
    # @return [Array] the value when it is an array, otherwise an empty array
    def array_or_empty(value)
      value.is_a?(Array) ? value : []
    end
  end

  # The outcome of a {Client#track} call.
  #
  # @!attribute [r] status
  #   @return [String, nil] the status Dregs reported, normally +"success"+
  # @!attribute [r] id
  #   @return [String, nil] the event's identifier, either the one you supplied or one Dregs
  #     generated; nil when the event was not recorded
  # @!attribute [r] fingerprint
  #   @return [String, nil] the device fingerprint Dregs resolved, for events that carried a device
  #     signature; server-side events do not, so this is normally nil
  # @!attribute [r] raw
  #   @return [Hash] the response body as received
  class TrackResult
    attr_reader :status, :id, :fingerprint, :raw

    # @api private
    def initialize(status:, id:, fingerprint:, raw: {})
      @status = status
      @id = id
      @fingerprint = fingerprint
      @raw = raw
    end

    # Whether Dregs recorded the event.
    #
    # This is false for the handful of rejections Dregs answers quietly, rather than naming the
    # check that failed: an event from an origin the credential does not allow, or one carrying a
    # malformed device signature or an unusable event id. Ingestion failures that are yours to act
    # on (a bad request, an unknown key, an exhausted quota, a rate limit) raise instead of landing
    # here.
    #
    # @return [Boolean]
    def accepted?
      !id.nil?
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        status: payload["status"],
        id: payload["id"],
        fingerprint: payload["fingerprint"],
        raw: payload
      )
    end
  end

  # A label Dregs applied to an identity, from an analyzer or a badge rule.
  #
  # @!attribute [r] slug
  #   @return [String, nil] the stable identifier, such as +"behavior.account-takeover-signal"+
  # @!attribute [r] name
  #   @return [String, nil] the human-readable name shown in the dashboard
  # @!attribute [r] type
  #   @return [String, nil] the badge's severity or kind
  # @!attribute [r] explanation
  #   @return [String, nil] why the badge was applied
  # @!attribute [r] metadata
  #   @return [Hash] the details behind it
  # @!attribute [r] raw
  #   @return [Hash] the badge as received
  class Badge
    attr_reader :slug, :name, :type, :explanation, :metadata, :raw

    # @api private
    def initialize(slug:, name:, type:, explanation:, metadata: {}, raw: {})
      @slug = slug
      @name = name
      @type = type
      @explanation = explanation
      @metadata = metadata
      @raw = raw
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        slug: payload["slug"],
        name: payload["name"],
        type: payload["type"],
        explanation: payload["explanation"],
        metadata: Parsing.hash_or_empty(payload["metadata"]),
        raw: payload
      )
    end
  end

  # One analyzer's finding, and the reasoning behind a slice of a score.
  #
  # @!attribute [r] category
  #   @return [Symbol, nil] the category the observation contributes to
  # @!attribute [r] id
  #   @return [String, nil] the analyzer's identifier, such as +"humanity.user-agent"+
  # @!attribute [r] label
  #   @return [String, nil] a human-readable name for the analyzer
  # @!attribute [r] explanation
  #   @return [String, nil] a sentence describing what the analyzer found
  # @!attribute [r] value
  #   @return [Float, nil] 0.0 for entirely suspicious, 1.0 for entirely legitimate
  # @!attribute [r] confidence
  #   @return [Float, nil] how sure the analyzer is, from 0.0 to 1.0
  # @!attribute [r] weight
  #   @return [Float, nil] how heavily this observation counts toward the category score
  # @!attribute [r] metadata
  #   @return [Hash] the counts and details behind the finding
  # @!attribute [r] raw
  #   @return [Hash] the observation as received
  class Observation
    attr_reader :category, :id, :label, :explanation, :value, :confidence, :weight, :metadata, :raw

    # @api private
    def initialize(category:, id:, label:, explanation:, value:, confidence:, weight:, metadata: {}, raw: {})
      @category = category
      @id = id
      @label = label
      @explanation = explanation
      @value = value
      @confidence = confidence
      @weight = weight
      @metadata = metadata
      @raw = raw
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        category: Category.parse(payload["category"]),
        id: payload["id"],
        label: payload["label"],
        explanation: payload["explanation"],
        value: payload["value"],
        confidence: payload["confidence"],
        weight: payload["weight"],
        metadata: Parsing.hash_or_empty(payload["metadata"]),
        raw: payload
      )
    end
  end

  # One category's score.
  #
  # @!attribute [r] category
  #   @return [Symbol, nil] the category scored
  # @!attribute [r] value
  #   @return [Integer, nil] a score from 0 (worst) to 100 (best)
  # @!attribute [r] observations
  #   @return [Array<Observation>] the observations behind the score, empty on the result of
  #     {Identities#scores}, which reports the scores alone; the observations come from
  #     {Identities#analysis}
  # @!attribute [r] raw
  #   @return [Hash] the score as received
  class Score
    attr_reader :category, :value, :observations, :raw

    # @api private
    def initialize(category:, value:, observations: [], raw: {})
      @category = category
      @value = value
      @observations = observations
      @raw = raw
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        category: Category.parse(payload["category"]),
        value: payload["value"],
        observations: Parsing.array_or_empty(payload["observations"]).map { |o| Observation.from_api(o) },
        raw: payload
      )
    end
  end

  # An identity's four category scores.
  #
  # Enumerable over {Score}, and also offering the four categories by name:
  #
  #   scores = client.identities.scores("user_12345")
  #
  #   hold_for_review if scores.authenticity && scores.authenticity < 40
  #
  # A category Dregs has not scored yet is absent from the collection, and its named accessor
  # returns nil. A brand-new identity therefore comes back empty.
  class Scores
    include Enumerable

    # @return [Array<Score>] the scores Dregs has computed, in the order it sent them
    attr_reader :to_a

    # @api private
    def initialize(scores = [])
      @to_a = scores.freeze
    end

    # @yieldparam score [Score]
    # @return [Enumerator, self]
    def each(&block)
      return to_enum(:each) unless block

      to_a.each(&block)

      self
    end

    # @return [Integer] how many categories have been scored
    def size
      to_a.size
    end
    alias length size

    # @return [Boolean] whether no category has been scored yet
    def empty?
      to_a.empty?
    end

    # @param index [Integer]
    # @return [Score, nil]
    def [](index)
      to_a[index]
    end

    # Returns the {Score} for a category, or nil when it has not been scored.
    #
    # @param category [Symbol] one of {Category::ALL}
    # @return [Score, nil]
    def get(category)
      to_a.find { |score| score.category == category }
    end

    # How likely it is that a person, rather than a script, is behind the account.
    #
    # @return [Integer, nil]
    def humanity
      value_for(Category::HUMANITY)
    end

    # How genuine the details on the account look.
    #
    # @return [Integer, nil]
    def authenticity
      value_for(Category::AUTHENTICITY)
    end

    # How distinct the account is from others in the same tenant.
    #
    # @return [Integer, nil]
    def uniqueness
      value_for(Category::UNIQUENESS)
    end

    # How ordinary the account's activity looks.
    #
    # @return [Integer, nil]
    def behavior
      value_for(Category::BEHAVIOR)
    end

    # @api private
    def self.from_api(payload)
      new(Parsing.array_or_empty(payload).map { |score| Score.from_api(score) })
    end

    private

    def value_for(category)
      get(category)&.value
    end
  end

  # A user Dregs is tracking, and their current scores.
  #
  # +id+ is your own identifier for the user, the one you pass to {Client#track} and to
  # +dregs.identify()+ in the browser tracker, not an internal Dregs id.
  #
  # @!attribute [r] id
  #   @return [String, nil] your identifier for the user
  # @!attribute [r] display_name
  #   @return [String, nil] the name Dregs resolved from the attributes you have sent
  # @!attribute [r] display_email
  #   @return [String, nil] the email Dregs resolved
  # @!attribute [r] display_username
  #   @return [String, nil] the username Dregs resolved
  # @!attribute [r] humanity_score
  #   @return [Integer, nil]
  # @!attribute [r] authenticity_score
  #   @return [Integer, nil]
  # @!attribute [r] uniqueness_score
  #   @return [Integer, nil]
  # @!attribute [r] behavior_score
  #   @return [Integer, nil]
  # @!attribute [r] created_at
  #   @return [Time, nil] when Dregs first saw this user
  # @!attribute [r] updated_at
  #   @return [Time, nil]
  # @!attribute [r] last_tracked_at
  #   @return [Time, nil] the most recent event
  # @!attribute [r] last_scored_at
  #   @return [Time, nil] the most recent analysis cycle
  # @!attribute [r] disregarded
  #   @return [Boolean] whether the identity is excluded from fraud analysis
  # @!attribute [r] badges
  #   @return [Array<Badge>]
  # @!attribute [r] data
  #   @return [Hash] every attribute you have sent for this user
  # @!attribute [r] raw
  #   @return [Hash] the identity as received
  class Identity
    attr_reader :id, :display_name, :display_email, :display_username, :humanity_score,
                :authenticity_score, :uniqueness_score, :behavior_score, :created_at, :updated_at,
                :last_tracked_at, :last_scored_at, :disregarded, :badges, :data, :raw

    # @api private
    def initialize(attributes)
      @id = attributes[:id]
      @display_name = attributes[:display_name]
      @display_email = attributes[:display_email]
      @display_username = attributes[:display_username]
      @humanity_score = attributes[:humanity_score]
      @authenticity_score = attributes[:authenticity_score]
      @uniqueness_score = attributes[:uniqueness_score]
      @behavior_score = attributes[:behavior_score]
      @created_at = attributes[:created_at]
      @updated_at = attributes[:updated_at]
      @last_tracked_at = attributes[:last_tracked_at]
      @last_scored_at = attributes[:last_scored_at]
      @disregarded = attributes.fetch(:disregarded, false)
      @badges = attributes.fetch(:badges, [])
      @data = attributes.fetch(:data, {})
      @raw = attributes.fetch(:raw, {})
    end

    # Whether the identity is excluded from fraud analysis.
    #
    # @return [Boolean]
    def disregarded?
      disregarded
    end

    # The identity's scores, as a {Scores} for parity with {Identities#scores}.
    #
    # @return [Scores]
    def scores
      pairs = [
        [Category::HUMANITY, humanity_score],
        [Category::AUTHENTICITY, authenticity_score],
        [Category::UNIQUENESS, uniqueness_score],
        [Category::BEHAVIOR, behavior_score]
      ]

      Scores.new(
        pairs.reject { |(_, value)| value.nil? }
             .map { |(category, value)| Score.new(category: category, value: value) }
      )
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        id: payload["id"],
        display_name: payload["displayName"],
        display_email: payload["displayEmail"],
        display_username: payload["displayUsername"],
        humanity_score: payload["humanityScore"],
        authenticity_score: payload["authenticityScore"],
        uniqueness_score: payload["uniquenessScore"],
        behavior_score: payload["behaviorScore"],
        created_at: Parsing.time(payload["createdAt"]),
        updated_at: Parsing.time(payload["updatedAt"]),
        last_tracked_at: Parsing.time(payload["lastTrackedAt"]),
        last_scored_at: Parsing.time(payload["lastScoredAt"]),
        disregarded: payload["disregarded"] == true,
        badges: Parsing.array_or_empty(payload["badges"]).map { |badge| Badge.from_api(badge) },
        data: Parsing.hash_or_empty(payload["data"]),
        raw: payload
      )
    end
  end

  # One analysis cycle: the scores an identity was given, and why.
  #
  # @!attribute [r] id
  #   @return [Integer, nil] the cycle's identifier
  # @!attribute [r] identity_id
  #   @return [String, nil] the identity that was analyzed
  # @!attribute [r] scores
  #   @return [Scores] the category scores, each carrying its observations
  # @!attribute [r] event_count
  #   @return [Integer, nil] how many events the cycle considered
  # @!attribute [r] device_count
  #   @return [Integer, nil] how many devices the cycle considered
  # @!attribute [r] duration_millis
  #   @return [Integer, nil] how long the cycle took
  # @!attribute [r] started_at
  #   @return [Time, nil]
  # @!attribute [r] finished_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the cycle as received
  class Analysis
    attr_reader :id, :identity_id, :scores, :event_count, :device_count, :duration_millis,
                :started_at, :finished_at, :raw

    # @api private
    def initialize(attributes)
      @id = attributes[:id]
      @identity_id = attributes[:identity_id]
      @scores = attributes.fetch(:scores) { Scores.new }
      @event_count = attributes[:event_count]
      @device_count = attributes[:device_count]
      @duration_millis = attributes[:duration_millis]
      @started_at = attributes[:started_at]
      @finished_at = attributes[:finished_at]
      @raw = attributes.fetch(:raw, {})
    end

    # Every observation from the cycle, across all four categories.
    #
    # This is the flat list to log or render when you need to show why an identity scored the way
    # it did; +scores+ keeps them grouped by category.
    #
    # @return [Array<Observation>]
    def observations
      scores.flat_map(&:observations)
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        id: payload["id"],
        identity_id: payload["identityId"],
        scores: Scores.from_api(payload["scores"]),
        event_count: payload["eventCount"],
        device_count: payload["deviceCount"],
        duration_millis: payload["durationMillis"],
        started_at: Parsing.time(payload["startedAt"]),
        finished_at: Parsing.time(payload["finishedAt"]),
        raw: payload
      )
    end
  end
end
