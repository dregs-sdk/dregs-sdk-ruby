# frozen_string_literal: true

require "uri"

require_relative "models"

module Dregs
  # What the namespaces on {Client} have in common: escaping path segments, checking arguments
  # before anything leaves the process, and paging.
  #
  # The namespaces themselves are thin. Each method names the endpoint and hands the response to a
  # model; the transport, the retries, and the error mapping all live on {Client}.
  #
  # @api private
  class Resource
    # The two directions a list can be sorted in.
    ORDERS = %w[asc desc].freeze

    # @api private
    # @param client [Client]
    def initialize(client)
      @client = client
    end

    private

    # Escapes one path segment, refusing an empty one.
    #
    # Ids are the caller's own and routinely contain characters that need escaping, an email
    # address being the common one. A space is sent as +%20+ rather than +, and a slash is escaped
    # so it cannot change the route.
    def segment(value, what)
      raise ArgumentError, "#{what} is required." if value.nil? || value.to_s.empty?

      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def identity_segment(identity_id)
      segment(identity_id, "An identity id")
    end

    # Fetches one page of a list.
    #
    # @param path [String] the list endpoint
    # @param model [Class] the model each item is parsed into
    # @param filters [Hash] the list's own query parameters, nil for those the caller left out
    def list_page(path, model, filters, page:, page_size:, sort:, order:)
      params = list_params(filters, page_size: page_size, sort: sort, order: order)

      fetch_page(path, model, params, page_number(page))
    end

    # Walks every page of a list, fetching each as the one before it runs out.
    #
    # The arguments are checked now rather than when the first page is fetched, so a bad one
    # raises where the call was made.
    def list_every(path, model, filters, page_size:, sort:, order:, &block)
      params = list_params(filters, page_size: page_size, sort: sort, order: order)

      items = Enumerator.new do |yielder|
        number = 0

        loop do
          page = fetch_page(path, model, params, number)

          page.each { |item| yielder << item }

          break unless page.has_next?

          number += 1
        end
      end

      return items unless block

      items.each(&block)

      nil
    end

    def fetch_page(path, model, params, number)
      Page.from_api(@client.request(:get, path, params: params.merge("pageNumber" => number)), model)
    end

    def list_params(filters, page_size:, sort:, order:)
      filters.merge("pageSize" => page_size, "sort" => sort, "order" => order_param(order))
    end

    def page_number(page)
      raise ArgumentError, "Pages are numbered from 0." unless page.is_a?(Integer) && page >= 0

      page
    end

    def order_param(order)
      return nil if order.nil?

      raise ArgumentError, "order is :asc or :desc." unless ORDERS.include?(order.to_s.downcase)

      order.to_s.upcase
    end

    def attributes_hash(attributes)
      return {} if attributes.nil?

      return attributes if attributes.is_a?(Hash)

      raise ArgumentError, "attributes must be a hash, such as { name: \"Acme Inc\" }."
    end

    def parse_each(model, payload)
      items = Parsing.array_or_empty(payload).grep(Hash)

      items.map { |item| model.from_api(item) }
    end
  end
end
