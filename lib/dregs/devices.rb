# frozen_string_literal: true

require_relative "models"
require_relative "resource"

module Dregs
  # The +client.devices+ namespace: the browsers and devices Dregs has seen, identified by their
  # fingerprints.
  class Devices < Resource
    # Returns one page of devices, most recently seen first. Use {#list_all} to walk every page.
    #
    # @param identity [String, nil] only devices this identity was seen on
    # @param term [String, nil] free text matched against fingerprints, addresses, places, and user
    #   agents
    # @param page [Integer] the page to return, counting from 0
    # @param page_size [Integer, nil] items per page, at most 100
    # @param sort [String, nil] the field to sort on, such as +"lastSeenAt"+ or +"country"+
    # @param order [Symbol, String, nil] +:asc+ or +:desc+
    # @return [Page<Device>]
    # @raise [ArgumentError] the page is negative or the order is not one of the two
    def list(identity: nil, term: nil, page: 0, page_size: nil, sort: nil, order: nil)
      filters = { "identity" => identity, "term" => term }

      list_page("/devices", Device, filters, page: page, page_size: page_size, sort: sort, order: order)
    end

    # Walks every device that matches, fetching pages as it goes. Takes the filters {#list} does.
    #
    # @return [Enumerator<Device>] a lazy enumerator, which fetches a page only when the items
    #   before it have been used up; nil when a block is given, which is called with each device
    # @raise [ArgumentError] the order is not one of the two
    def list_all(identity: nil, term: nil, page_size: nil, sort: nil, order: nil, &block)
      filters = { "identity" => identity, "term" => term }

      list_every("/devices", Device, filters, page_size: page_size, sort: sort, order: order, &block)
    end

    # Returns the device with this fingerprint.
    #
    # @param fingerprint [String] the device's fingerprint
    # @return [Device]
    # @raise [NotFoundError] no device has this fingerprint
    def get(fingerprint)
      Device.from_api(@client.request(:get, path_for(fingerprint)))
    end

    # Sets whether the device is disregarded, and returns it.
    #
    # A disregarded device, such as a shared office machine, no longer links the identities seen
    # on it.
    #
    #   client.devices.update("a1b2c3d4e5", disregarded: true)
    #
    # @param fingerprint [String] the device's fingerprint
    # @param disregarded [Boolean] whether to disregard it
    # @return [Device]
    # @raise [NotFoundError] no device has this fingerprint
    def update(fingerprint, disregarded:)
      body = { "disregarded" => disregarded ? true : false }

      Device.from_api(@client.request(:patch, path_for(fingerprint), body: body))
    end

    private

    def path_for(fingerprint)
      "/devices/#{segment(fingerprint, "A device fingerprint")}"
    end
  end
end
