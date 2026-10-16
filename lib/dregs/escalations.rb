# frozen_string_literal: true

require_relative "models"
require_relative "resource"

module Dregs
  # The +client.escalations+ namespace: the escalations your escalation rules open, and moving
  # them along.
  class Escalations < Resource
    # The statuses an escalation moves through.
    STATUSES = %w[OPEN ACKNOWLEDGED CLOSED].freeze

    # Returns one page of escalations, newest first. Use {#list_all} to walk every page.
    #
    # @param status [Symbol, String, nil] only escalations in this status: +:open+,
    #   +:acknowledged+, or +:closed+
    # @param severity [Symbol, String, nil] only escalations of this severity: +:info+, +:warning+,
    #   or +:critical+
    # @param identity [String, nil] only escalations about this identity
    # @param rule [Integer, String, nil] only escalations opened by the escalation rule with this id
    # @param page [Integer] the page to return, counting from 0
    # @param page_size [Integer, nil] items per page, at most 100
    # @param sort [String, nil] the field to sort on, such as +"openedAt"+ or +"severity"+
    # @param order [Symbol, String, nil] +:asc+ or +:desc+
    # @return [Page<Escalation>]
    # @raise [ArgumentError] the status is not one of the three, the page is negative, or the order
    #   is not one of the two
    def list(status: nil, severity: nil, identity: nil, rule: nil, page: 0, page_size: nil, sort: nil,
             order: nil)
      filters = list_filters(status: status, severity: severity, identity: identity, rule: rule)

      list_page(
        "/escalations", Escalation, filters, page: page, page_size: page_size, sort: sort, order: order
      )
    end

    # Walks every escalation that matches, fetching pages as it goes. Takes the filters {#list}
    # does.
    #
    #   client.escalations.list_all(status: :open, severity: :critical).each do |escalation|
    #     notify_on_call(escalation.identity.id)
    #     client.escalations.update(escalation.id, status: :acknowledged)
    #   end
    #
    # @return [Enumerator<Escalation>] a lazy enumerator, which fetches a page only when the items
    #   before it have been used up; nil when a block is given, which is called with each escalation
    # @raise [ArgumentError] the status is not one of the three, or the order is not one of the two
    def list_all(status: nil, severity: nil, identity: nil, rule: nil, page_size: nil, sort: nil, order: nil,
                 &block)
      filters = list_filters(status: status, severity: severity, identity: identity, rule: rule)

      list_every("/escalations", Escalation, filters, page_size: page_size, sort: sort, order: order, &block)
    end

    # Returns the escalation with this id.
    #
    # @param escalation_id [Integer, String]
    # @return [Escalation]
    # @raise [NotFoundError] no escalation has this id
    def get(escalation_id)
      Escalation.from_api(@client.request(:get, path_for(escalation_id)))
    end

    # Moves the escalation to +status+ and returns it.
    #
    # @param escalation_id [Integer, String]
    # @param status [Symbol, String] +:open+, +:acknowledged+, or +:closed+
    # @return [Escalation]
    # @raise [NotFoundError] no escalation has this id
    # @raise [ArgumentError] the status is not one of the three
    def update(escalation_id, status:)
      body = { "status" => status_param(status) }

      Escalation.from_api(@client.request(:patch, path_for(escalation_id), body: body))
    end

    # Returns how many escalations are open, acknowledged, and closed.
    #
    # @return [EscalationSummary]
    def summary
      EscalationSummary.from_api(@client.request(:get, "/escalations/summary"))
    end

    private

    def path_for(escalation_id)
      "/escalations/#{segment(escalation_id, "An escalation id")}"
    end

    def list_filters(status:, severity:, identity:, rule:)
      {
        "status" => status.nil? ? nil : status_param(status),
        "severity" => severity.nil? || severity.to_s.empty? ? nil : severity.to_s.upcase,
        "identity" => identity,
        "rule" => rule
      }
    end

    def status_param(status)
      value = status.to_s.upcase if status.is_a?(String) || status.is_a?(Symbol)

      raise ArgumentError, "status is :open, :acknowledged, or :closed." unless STATUSES.include?(value)

      value
    end
  end
end
