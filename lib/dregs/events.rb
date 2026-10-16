# frozen_string_literal: true

require_relative "models"
require_relative "resource"

module Dregs
  # The +client.events+ namespace: reading the events Dregs has recorded. To record one, use
  # {Client#track}.
  class Events < Resource
    # Returns one page of events, newest first. Use {#list_all} to walk every page.
    #
    # @param identity [String, nil] only events from this identity
    # @param group [String, nil] only events sent with the group with this id
    # @param group_type [String, nil] only events sent with a group of this type
    # @param device [String, nil] only events from the device with this fingerprint
    # @param session [String, nil] only events from this browser session
    # @param term [String, nil] free text matched against event names and data
    # @param page [Integer] the page to return, counting from 0
    # @param page_size [Integer, nil] items per page, at most 100
    # @param sort [String, nil] the field to sort on, such as +"timestamp"+ or +"eventName"+
    # @param order [Symbol, String, nil] +:asc+ or +:desc+
    # @return [Page<Event>]
    # @raise [ArgumentError] the page is negative or the order is not one of the two
    def list(identity: nil, group: nil, group_type: nil, device: nil, session: nil, term: nil, page: 0,
             page_size: nil, sort: nil, order: nil)
      filters = list_filters(
        identity: identity, group: group, group_type: group_type, device: device, session: session, term: term
      )

      list_page("/events", Event, filters, page: page, page_size: page_size, sort: sort, order: order)
    end

    # Walks every event that matches, fetching pages as it goes. Takes the filters {#list} does.
    #
    #   client.events.list_all(identity: "user_12345").each do |event|
    #     puts "#{event.timestamp} #{event.name}"
    #   end
    #
    # @return [Enumerator<Event>] a lazy enumerator, which fetches a page only when the items before
    #   it have been used up; nil when a block is given, which is called with each event
    # @raise [ArgumentError] the order is not one of the two
    def list_all(identity: nil, group: nil, group_type: nil, device: nil, session: nil, term: nil,
                 page_size: nil, sort: nil, order: nil, &block)
      filters = list_filters(
        identity: identity, group: group, group_type: group_type, device: device, session: session, term: term
      )

      list_every("/events", Event, filters, page_size: page_size, sort: sort, order: order, &block)
    end

    # Returns the event with this id.
    #
    # @param event_id [String] the event's id, either the one you sent or one Dregs generated
    # @return [Event]
    # @raise [NotFoundError] no event has this id
    def get(event_id)
      Event.from_api(@client.request(:get, "/events/#{segment(event_id, "An event id")}"))
    end

    private

    def list_filters(identity:, group:, group_type:, device:, session:, term:)
      {
        "identity" => identity,
        "group" => group,
        "groupType" => group_type,
        "device" => device,
        "session" => session,
        "term" => term
      }
    end
  end
end
