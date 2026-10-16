# frozen_string_literal: true

require_relative "models"
require_relative "resource"

module Dregs
  # The +client.groups+ namespace: the organizations, teams, or workspaces your users belong to.
  #
  # {Client#track} already records groups and memberships as events arrive. These calls are for
  # reading them back, and for keeping Dregs in step when something changes outside an event, such
  # as a user leaving a team.
  #
  # A group is identified by its type and id together, so the calls that address one take both.
  class Groups < Resource
    # Returns one page of groups, most recently active first.
    #
    # The groups in a list leave out their attributes; {#get} returns them. Use {#list_all} to walk
    # every page.
    #
    # @param group_type [String, nil] only groups of this type, such as +"team"+
    # @param identity [String, nil] only groups this identity belongs to
    # @param term [String, nil] free text matched against group ids and names
    # @param page [Integer] the page to return, counting from 0
    # @param page_size [Integer, nil] items per page, at most 100
    # @param sort [String, nil] the field to sort on, such as +"displayName"+ or +"lastTrackedAt"+
    # @param order [Symbol, String, nil] +:asc+ or +:desc+
    # @return [Page<Group>]
    # @raise [ArgumentError] the page is negative or the order is not one of the two
    def list(group_type: nil, identity: nil, term: nil, page: 0, page_size: nil, sort: nil, order: nil)
      filters = list_filters(group_type: group_type, identity: identity, term: term)

      list_page("/groups", Group, filters, page: page, page_size: page_size, sort: sort, order: order)
    end

    # Walks every group that matches, fetching pages as it goes. Takes the filters {#list} does.
    #
    #   client.groups.list_all(group_type: "team", identity: "user_12345").each do |team|
    #     puts "#{team.id} #{team.display_name}"
    #   end
    #
    # @return [Enumerator<Group>] a lazy enumerator, which fetches a page only when the items before
    #   it have been used up; nil when a block is given, which is called with each group
    # @raise [ArgumentError] the order is not one of the two
    def list_all(group_type: nil, identity: nil, term: nil, page_size: nil, sort: nil, order: nil, &block)
      filters = list_filters(group_type: group_type, identity: identity, term: term)

      list_every("/groups", Group, filters, page_size: page_size, sort: sort, order: order, &block)
    end

    # Returns the group, with its attributes.
    #
    #   group = client.groups.get("organization", "org_678")
    #
    #   group.identity_count  #=> 12
    #
    # @param group_type [String] the kind of group, such as +"organization"+
    # @param group_id [String] your own id for the group
    # @return [Group]
    # @raise [NotFoundError] no group of this type has this id
    def get(group_type, group_id)
      Group.from_api(@client.request(:get, path_for(group_type, group_id)))
    end

    # Creates a group, or merges +attributes:+ into the group that already has this type and id,
    # so it is safe to call on every sync.
    #
    #   client.groups.create("org_678", attributes: { name: "Acme Inc", plan: "enterprise" })
    #
    # @param group_id [String] your own id for the group
    # @param group_type [String, nil] the kind of group; +"organization"+ when omitted
    # @param attributes [Hash, nil] attributes such as a name or plan
    # @return [Group]
    def create(group_id, group_type: nil, attributes: nil)
      segment(group_id, "A group id")

      group_type = Client::DEFAULT_GROUP_TYPE if group_type.nil? || group_type.to_s.empty?
      body = { "type" => group_type.to_s, "id" => group_id.to_s, "attributes" => attributes_hash(attributes) }

      Group.from_api(@client.request(:post, "/groups", body: body))
    end

    # Merges +attributes+ into the group and returns it.
    #
    #   client.groups.update("organization", "org_678", { plan: "business" })
    #
    # @param group_type [String] the kind of group
    # @param group_id [String] your own id for the group
    # @param attributes [Hash] the attributes to merge
    # @return [Group]
    # @raise [NotFoundError] no group of this type has this id
    def update(group_type, group_id, attributes)
      body = { "attributes" => attributes_hash(attributes) }

      Group.from_api(@client.request(:patch, path_for(group_type, group_id), body: body))
    end

    # Makes the identity a member of the group. Adding an existing member does nothing.
    #
    # @param group_type [String] the kind of group
    # @param group_id [String] your own id for the group
    # @param identity_id [String] your own id for the user
    # @return [nil]
    # @raise [NotFoundError] the group or the identity is unknown
    def add_member(group_type, group_id, identity_id)
      @client.request(:put, member_path(group_type, group_id, identity_id))

      nil
    end

    # Removes the identity from the group, such as when a user leaves a team.
    #
    # @param group_type [String] the kind of group
    # @param group_id [String] your own id for the group
    # @param identity_id [String] your own id for the user
    # @return [nil]
    # @raise [NotFoundError] the group or the identity is unknown
    def remove_member(group_type, group_id, identity_id)
      @client.request(:delete, member_path(group_type, group_id, identity_id))

      nil
    end

    private

    def path_for(group_type, group_id)
      "/groups/#{segment(group_type, "A group type")}/#{segment(group_id, "A group id")}"
    end

    def member_path(group_type, group_id, identity_id)
      "#{path_for(group_type, group_id)}/identities/#{identity_segment(identity_id)}"
    end

    def list_filters(group_type:, identity:, term:)
      { "type" => group_type, "identity" => identity, "term" => term }
    end
  end
end
