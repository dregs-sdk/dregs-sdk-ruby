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

    # @param value [Object]
    # @return [Integer] the value when it is an integer, otherwise 0
    def integer_or_zero(value)
      value.is_a?(Integer) ? value : 0
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
    # This is false in the uncommon case where Dregs accepts the request without recording an
    # event. A server-side integration holding a valid secret key should not normally see it, so it
    # is worth a log line if you do. Ingestion failures that are yours to act on (a bad request, an
    # unknown key, an exhausted quota, a rate limit) raise instead of landing here.
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

  # One page of a list call.
  #
  # Enumerable over the items on this page. Pages are numbered from 0. To walk every page, use the
  # namespace's +list_all+ rather than looping on +page_number+ yourself.
  #
  #   page = client.identities.list(term: "example.com")
  #
  #   page.map(&:id)
  #   page.has_next?  #=> whether another page follows
  #
  # @!attribute [r] page_number
  #   @return [Integer] this page's number, counting from 0
  # @!attribute [r] page_size
  #   @return [Integer] the most items a page holds
  # @!attribute [r] total_pages
  #   @return [Integer] how many pages there are in all
  # @!attribute [r] total_elements
  #   @return [Integer] how many items there are across every page
  # @!attribute [r] raw
  #   @return [Hash] the page as received
  class Page
    include Enumerable

    # @return [Array] the items on this page
    attr_reader :to_a

    attr_reader :page_number, :page_size, :total_pages, :total_elements, :raw

    # @api private
    def initialize(attributes = {})
      @to_a = attributes.fetch(:items, []).freeze
      @page_number = attributes.fetch(:page_number, 0)
      @page_size = attributes.fetch(:page_size, 0)
      @total_pages = attributes.fetch(:total_pages, 0)
      @total_elements = attributes.fetch(:total_elements, 0)
      @first = attributes.fetch(:first, true)
      @last = attributes.fetch(:last, true)
      @raw = attributes.fetch(:raw, {})
    end

    # @yieldparam item [Object]
    # @return [Enumerator, self]
    def each(&block)
      return to_enum(:each) unless block

      to_a.each(&block)

      self
    end

    # @return [Integer] how many items are on this page
    def size
      to_a.size
    end
    alias length size

    # @return [Boolean] whether this page has no items
    def empty?
      to_a.empty?
    end

    # @param index [Integer]
    # @return [Object, nil]
    def [](index)
      to_a[index]
    end

    # Whether this is the first page.
    #
    # @return [Boolean]
    def first?
      @first
    end

    # Whether this is the last page.
    #
    # @return [Boolean]
    def last?
      @last
    end

    # Whether another page follows this one.
    #
    # An empty page counts as the end even when the API did not mark it last, so a walk cannot
    # spin on a list that shrank underneath it.
    #
    # @return [Boolean]
    def next?
      !last? && !empty?
    end
    alias has_next? next?

    # @api private
    # @param payload [Hash] a +V1Page+ from the API
    # @param model [Class] the model each item is parsed into
    def self.from_api(payload, model)
      payload = Parsing.hash_or_empty(payload)
      items = Parsing.array_or_empty(payload["content"]).grep(Hash)

      new(
        items: items.map { |item| model.from_api(item) },
        page_number: Parsing.integer_or_zero(payload["pageNumber"]),
        page_size: Parsing.integer_or_zero(payload["pageSize"]),
        total_pages: Parsing.integer_or_zero(payload["totalPages"]),
        total_elements: Parsing.integer_or_zero(payload["totalElements"]),
        first: payload["first"] != false,
        last: payload["last"] != false,
        raw: payload
      )
    end
  end

  # A pointer to another resource: its id, a label for display, and its API path.
  #
  # @!attribute [r] id
  #   @return [String, nil] the resource's id
  # @!attribute [r] label
  #   @return [String, nil] a name for display
  # @!attribute [r] path
  #   @return [String, nil] the resource's path in the API
  # @!attribute [r] raw
  #   @return [Hash] the reference as received
  class Reference
    attr_reader :id, :label, :path, :raw

    # @api private
    def initialize(id:, label: nil, path: nil, raw: {})
      @id = id
      @label = label
      @path = path
      @raw = raw
    end

    # @api private
    # @return [Reference, nil] nil when the payload is not a hash
    def self.from_api(payload)
      return nil unless payload.is_a?(Hash)

      new(id: payload["id"], label: payload["label"], path: payload["path"], raw: payload)
    end
  end

  # A pointer to a group, as it appears on an event.
  #
  # @!attribute [r] type
  #   @return [String, nil] the kind of group, such as +"team"+
  # @!attribute [r] id
  #   @return [String, nil] your own id for the group
  # @!attribute [r] label
  #   @return [String, nil] a name for display
  # @!attribute [r] path
  #   @return [String, nil] the group's path in the API
  # @!attribute [r] raw
  #   @return [Hash] the reference as received
  class GroupReference
    attr_reader :type, :id, :label, :path, :raw

    # @api private
    def initialize(type:, id:, label: nil, path: nil, raw: {})
      @type = type
      @id = id
      @label = label
      @path = path
      @raw = raw
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        type: payload["type"],
        id: payload["id"],
        label: payload["label"],
        path: payload["path"],
        raw: payload
      )
    end
  end

  # An organization, team, workspace, or whatever your application groups users into.
  #
  # A group is identified by its +type+ and +id+ together, both your own. Dregs normalizes the type
  # to lower_snake_case.
  #
  # @!attribute [r] type
  #   @return [String, nil] the kind of group, such as +"organization"+ or +"team"+
  # @!attribute [r] id
  #   @return [String, nil] your own id for the group
  # @!attribute [r] display_name
  #   @return [String, nil] a name for display, taken from the group's attributes
  # @!attribute [r] identity_count
  #   @return [Integer, nil] how many identities are members
  # @!attribute [r] created_at
  #   @return [Time, nil]
  # @!attribute [r] updated_at
  #   @return [Time, nil]
  # @!attribute [r] last_tracked_at
  #   @return [Time, nil] the most recent event sent with the group
  # @!attribute [r] data
  #   @return [Hash] the group's attributes; empty on the groups of a list call, which leaves them
  #     out
  # @!attribute [r] raw
  #   @return [Hash] the group as received
  class Group
    attr_reader :type, :id, :display_name, :identity_count, :created_at, :updated_at, :last_tracked_at,
                :data, :raw

    # @api private
    def initialize(attributes)
      @type = attributes[:type]
      @id = attributes[:id]
      @display_name = attributes[:display_name]
      @identity_count = attributes[:identity_count]
      @created_at = attributes[:created_at]
      @updated_at = attributes[:updated_at]
      @last_tracked_at = attributes[:last_tracked_at]
      @data = attributes.fetch(:data, {})
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        type: payload["type"],
        id: payload["id"],
        display_name: payload["displayName"],
        identity_count: payload["identityCount"],
        created_at: Parsing.time(payload["createdAt"]),
        updated_at: Parsing.time(payload["updatedAt"]),
        last_tracked_at: Parsing.time(payload["lastTrackedAt"]),
        data: Parsing.hash_or_empty(payload["data"]),
        raw: payload
      )
    end
  end

  # An event Dregs recorded.
  #
  # @!attribute [r] id
  #   @return [String, nil] the event's id, either the one you sent or one Dregs generated
  # @!attribute [r] timestamp
  #   @return [Time, nil] when the event happened
  # @!attribute [r] identity
  #   @return [Reference, nil] the identity the event belongs to, if any
  # @!attribute [r] groups
  #   @return [Array<GroupReference>] the groups the event was sent with
  # @!attribute [r] fingerprint
  #   @return [String, nil] the device fingerprint, for events that carried a device signature
  # @!attribute [r] session
  #   @return [String, nil] the browser session, for events from the tracker
  # @!attribute [r] ip
  #   @return [String, nil] the address the event came from
  # @!attribute [r] url
  #   @return [String, nil] the page URL, for events from the tracker
  # @!attribute [r] source
  #   @return [String, nil] where the event came from, such as +"ruby-sdk"+
  # @!attribute [r] name
  #   @return [String, nil] your name for the event, such as +"user.signup"+
  # @!attribute [r] canonical_type
  #   @return [String, nil] the Dregs event type your name is mapped to, if it is mapped
  # @!attribute [r] data
  #   @return [Hash] the event's attributes, with sensitive values redacted
  # @!attribute [r] raw
  #   @return [Hash] the event as received
  class Event
    attr_reader :id, :timestamp, :identity, :groups, :fingerprint, :session, :ip, :url, :source, :name,
                :canonical_type, :data, :raw

    # @api private
    def initialize(attributes)
      @id = attributes[:id]
      @timestamp = attributes[:timestamp]
      @identity = attributes[:identity]
      @groups = attributes.fetch(:groups, [])
      @fingerprint = attributes[:fingerprint]
      @session = attributes[:session]
      @ip = attributes[:ip]
      @url = attributes[:url]
      @source = attributes[:source]
      @name = attributes[:name]
      @canonical_type = attributes[:canonical_type]
      @data = attributes.fetch(:data, {})
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)
      groups = Parsing.array_or_empty(payload["groups"]).grep(Hash)

      new(
        id: payload["id"],
        timestamp: Parsing.time(payload["timestamp"]),
        identity: Reference.from_api(payload["identity"]),
        groups: groups.map { |group| GroupReference.from_api(group) },
        fingerprint: payload["fingerprint"],
        session: payload["session"],
        ip: payload["ip"],
        url: payload["url"],
        source: payload["eventSource"],
        name: payload["eventName"],
        canonical_type: payload["canonicalType"],
        data: Parsing.hash_or_empty(payload["eventData"]),
        raw: payload
      )
    end
  end

  # A browser or device Dregs has seen, identified by its fingerprint.
  #
  # @!attribute [r] fingerprint
  #   @return [String, nil]
  # @!attribute [r] ip
  #   @return [String, nil] the address it was last seen from
  # @!attribute [r] asn
  #   @return [String, nil] the network the address belongs to
  # @!attribute [r] asn_label
  #   @return [String, nil] a name for that network
  # @!attribute [r] user_agent
  #   @return [String, nil]
  # @!attribute [r] city
  #   @return [String, nil]
  # @!attribute [r] region
  #   @return [String, nil]
  # @!attribute [r] country
  #   @return [String, nil]
  # @!attribute [r] country_code
  #   @return [String, nil]
  # @!attribute [r] timezone
  #   @return [String, nil]
  # @!attribute [r] latitude
  #   @return [Float, nil]
  # @!attribute [r] longitude
  #   @return [Float, nil]
  # @!attribute [r] disregarded
  #   @return [Boolean] whether the device no longer links the identities seen on it
  # @!attribute [r] first_seen_at
  #   @return [Time, nil]
  # @!attribute [r] last_seen_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the device as received
  class Device
    attr_reader :fingerprint, :ip, :asn, :asn_label, :user_agent, :city, :region, :country, :country_code,
                :timezone, :latitude, :longitude, :disregarded, :first_seen_at, :last_seen_at, :raw

    # @api private
    def initialize(attributes)
      @fingerprint = attributes[:fingerprint]
      @ip = attributes[:ip]
      @asn = attributes[:asn]
      @asn_label = attributes[:asn_label]
      @user_agent = attributes[:user_agent]
      @city = attributes[:city]
      @region = attributes[:region]
      @country = attributes[:country]
      @country_code = attributes[:country_code]
      @timezone = attributes[:timezone]
      @latitude = attributes[:latitude]
      @longitude = attributes[:longitude]
      @disregarded = attributes.fetch(:disregarded, false)
      @first_seen_at = attributes[:first_seen_at]
      @last_seen_at = attributes[:last_seen_at]
      @raw = attributes.fetch(:raw, {})
    end

    # Whether the device no longer links the identities seen on it.
    #
    # @return [Boolean]
    def disregarded?
      disregarded
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        fingerprint: payload["fingerprint"],
        ip: payload["ip"],
        asn: payload["asn"],
        asn_label: payload["asnLabel"],
        user_agent: payload["userAgent"],
        city: payload["city"],
        region: payload["region"],
        country: payload["country"],
        country_code: payload["countryCode"],
        timezone: payload["timezone"],
        latitude: payload["latitude"],
        longitude: payload["longitude"],
        disregarded: payload["disregarded"] == true,
        first_seen_at: Parsing.time(payload["firstSeenAt"]),
        last_seen_at: Parsing.time(payload["lastSeenAt"]),
        raw: payload
      )
    end
  end

  # Another identity Dregs believes is connected to this one, such as by a shared device.
  #
  # @!attribute [r] identity_id
  #   @return [String, nil] the linked identity's id
  # @!attribute [r] display_name
  #   @return [String, nil] the linked identity's display name
  # @!attribute [r] type
  #   @return [String, nil] how they are linked, such as +"SAME_DEVICE"+ or +"SHARED_IP"+
  # @!attribute [r] value
  #   @return [Float, nil] how strongly they are linked, from 0.0 to 1.0
  # @!attribute [r] confidence
  #   @return [Float, nil] how sure Dregs is of the link, from 0.0 to 1.0
  # @!attribute [r] explanation
  #   @return [String, nil] a sentence describing the link
  # @!attribute [r] metadata
  #   @return [Hash] the details behind it
  # @!attribute [r] created_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the link as received
  class LinkedIdentity
    attr_reader :identity_id, :display_name, :type, :value, :confidence, :explanation, :metadata,
                :created_at, :raw

    # @api private
    def initialize(attributes)
      @identity_id = attributes[:identity_id]
      @display_name = attributes[:display_name]
      @type = attributes[:type]
      @value = attributes[:value]
      @confidence = attributes[:confidence]
      @explanation = attributes[:explanation]
      @metadata = attributes.fetch(:metadata, {})
      @created_at = attributes[:created_at]
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        identity_id: payload["targetIdentityId"],
        display_name: payload["targetDisplayName"],
        type: payload["type"],
        value: payload["value"],
        confidence: payload["confidence"],
        explanation: payload["explanation"],
        metadata: Parsing.hash_or_empty(payload["metadata"]),
        created_at: Parsing.time(payload["createdAt"]),
        raw: payload
      )
    end
  end

  # The scores one past analysis cycle produced.
  #
  # @!attribute [r] cycle_id
  #   @return [Integer, nil] the cycle's id, which {Identities#analysis} accepts as +cycle_id:+ to
  #     fetch that cycle's observations
  # @!attribute [r] humanity
  #   @return [Integer, nil]
  # @!attribute [r] authenticity
  #   @return [Integer, nil]
  # @!attribute [r] uniqueness
  #   @return [Integer, nil]
  # @!attribute [r] behavior
  #   @return [Integer, nil]
  # @!attribute [r] event_count
  #   @return [Integer, nil] how many events the cycle considered
  # @!attribute [r] device_count
  #   @return [Integer, nil] how many devices the cycle considered
  # @!attribute [r] finished_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the entry as received
  class ScoreHistoryEntry
    attr_reader :cycle_id, :humanity, :authenticity, :uniqueness, :behavior, :event_count, :device_count,
                :finished_at, :raw

    # @api private
    def initialize(attributes)
      @cycle_id = attributes[:cycle_id]
      @humanity = attributes[:humanity]
      @authenticity = attributes[:authenticity]
      @uniqueness = attributes[:uniqueness]
      @behavior = attributes[:behavior]
      @event_count = attributes[:event_count]
      @device_count = attributes[:device_count]
      @finished_at = attributes[:finished_at]
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        cycle_id: payload["id"],
        humanity: payload["humanityScore"],
        authenticity: payload["authenticityScore"],
        uniqueness: payload["uniquenessScore"],
        behavior: payload["behaviorScore"],
        event_count: payload["eventCount"],
        device_count: payload["deviceCount"],
        finished_at: Parsing.time(payload["finishedAt"]),
        raw: payload
      )
    end
  end

  # A review of an identity's analysis, written by Dregs's AI reviewer.
  #
  # @!attribute [r] id
  #   @return [Integer, nil] the review's id
  # @!attribute [r] identity_id
  #   @return [String, nil]
  # @!attribute [r] status
  #   @return [String, nil] +"PENDING"+ until the review has run, then +"FINISHED"+ or +"FAILED"+
  # @!attribute [r] feedback
  #   @return [String, nil] the note you sent with the request, if any
  # @!attribute [r] summary
  #   @return [String, nil] the reviewer's findings, once it has run
  # @!attribute [r] error_message
  #   @return [String, nil] why the review failed, when it did
  # @!attribute [r] created_at
  #   @return [Time, nil]
  # @!attribute [r] completed_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the review as received
  class IdentityReview
    attr_reader :id, :identity_id, :status, :feedback, :summary, :error_message, :created_at,
                :completed_at, :raw

    # @api private
    def initialize(attributes)
      @id = attributes[:id]
      @identity_id = attributes[:identity_id]
      @status = attributes[:status]
      @feedback = attributes[:feedback]
      @summary = attributes[:summary]
      @error_message = attributes[:error_message]
      @created_at = attributes[:created_at]
      @completed_at = attributes[:completed_at]
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        id: payload["id"],
        identity_id: payload["identityId"],
        status: payload["status"],
        feedback: payload["userFeedback"],
        summary: payload["summary"],
        error_message: payload["errorMessage"],
        created_at: Parsing.time(payload["createdAt"]),
        completed_at: Parsing.time(payload["completedAt"]),
        raw: payload
      )
    end
  end

  # An escalation an escalation rule opened against an identity.
  #
  # @!attribute [r] id
  #   @return [Integer, nil] the escalation's id
  # @!attribute [r] status
  #   @return [String, nil] +"OPEN"+, +"ACKNOWLEDGED"+, or +"CLOSED"+
  # @!attribute [r] severity
  #   @return [String, nil] +"INFO"+, +"WARNING"+, or +"CRITICAL"+
  # @!attribute [r] identity
  #   @return [Reference, nil] the identity the escalation is about
  # @!attribute [r] rule
  #   @return [Reference, nil] the escalation rule that opened it
  # @!attribute [r] scores
  #   @return [Hash] the identity's scores when the escalation opened, by category name
  # @!attribute [r] opened_at
  #   @return [Time, nil]
  # @!attribute [r] acknowledged_at
  #   @return [Time, nil]
  # @!attribute [r] closed_at
  #   @return [Time, nil]
  # @!attribute [r] created_at
  #   @return [Time, nil]
  # @!attribute [r] raw
  #   @return [Hash] the escalation as received
  class Escalation
    attr_reader :id, :status, :severity, :identity, :rule, :scores, :opened_at, :acknowledged_at, :closed_at,
                :created_at, :raw

    # @api private
    def initialize(attributes)
      @id = attributes[:id]
      @status = attributes[:status]
      @severity = attributes[:severity]
      @identity = attributes[:identity]
      @rule = attributes[:rule]
      @scores = attributes.fetch(:scores, {})
      @opened_at = attributes[:opened_at]
      @acknowledged_at = attributes[:acknowledged_at]
      @closed_at = attributes[:closed_at]
      @created_at = attributes[:created_at]
      @raw = attributes.fetch(:raw, {})
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        id: payload["id"],
        status: payload["status"],
        severity: payload["severity"],
        identity: Reference.from_api(payload["identity"]),
        rule: Reference.from_api(payload["escalationRule"]),
        scores: Parsing.hash_or_empty(payload["scoreSnapshot"]),
        opened_at: Parsing.time(payload["openedAt"]),
        acknowledged_at: Parsing.time(payload["acknowledgedAt"]),
        closed_at: Parsing.time(payload["closedAt"]),
        created_at: Parsing.time(payload["createdAt"]),
        raw: payload
      )
    end
  end

  # How many escalations are in each status.
  #
  # @!attribute [r] open
  #   @return [Integer]
  # @!attribute [r] acknowledged
  #   @return [Integer]
  # @!attribute [r] closed
  #   @return [Integer]
  # @!attribute [r] raw
  #   @return [Hash] the summary as received
  class EscalationSummary
    attr_reader :open, :acknowledged, :closed, :raw

    # @api private
    def initialize(open: 0, acknowledged: 0, closed: 0, raw: {})
      @open = open
      @acknowledged = acknowledged
      @closed = closed
      @raw = raw
    end

    # @api private
    def self.from_api(payload)
      payload = Parsing.hash_or_empty(payload)

      new(
        open: Parsing.integer_or_zero(payload["open"]),
        acknowledged: Parsing.integer_or_zero(payload["acknowledged"]),
        closed: Parsing.integer_or_zero(payload["closed"]),
        raw: payload
      )
    end
  end
end
