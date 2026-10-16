# frozen_string_literal: true

RSpec.describe "listing and paging" do
  let(:client) { build_client }

  describe "list" do
    it "sends the page and the filters, and leaves out the unset ones" do
      requests = capture_requests(:get, "/identities", page_of([]))

      client.identities.list(term: "ada", page: 2, page_size: 50, sort: "humanityScore", order: :asc)

      expect(requests.last.uri.query_values).to eq(
        "term" => "ada",
        "pageNumber" => "2",
        "pageSize" => "50",
        "sort" => "humanityScore",
        "order" => "ASC"
      )
    end

    it "accepts the order as a string in either case" do
      requests = capture_requests(:get, "/devices", page_of([]))

      client.devices.list(order: "Desc")

      expect(requests.last.uri.query_values["order"]).to eq("DESC")
    end

    it "asks for the first page when none is given" do
      requests = capture_requests(:get, "/identities", page_of([]))

      client.identities.list

      expect(requests.last.uri.query_values).to eq("pageNumber" => "0")
    end

    it "returns a page that is enumerable and knows its position" do
      capture_requests(
        :get, "/identities", page_of([{ "id" => "a" }, { "id" => "b" }], last: false, total: 5)
      )

      page = client.identities.list

      expect(page).to be_a(Dregs::Page)
      expect(page.map(&:id)).to eq(%w[a b])
      expect(page.first).to be_a(Dregs::Identity)
      expect(page.size).to eq(2)
      expect(page[1].id).to eq("b")
      expect(page.page_number).to eq(0)
      expect(page.page_size).to eq(2)
      expect(page.total_pages).to eq(2)
      expect(page.total_elements).to eq(5)
      expect(page.first?).to be(true)
      expect(page.last?).to be(false)
      expect(page.has_next?).to be(true)
      expect(page.next?).to be(true)
      expect(page.raw["numberOfElements"]).to eq(2)
    end

    it "refuses a negative page before any request" do
      expect { client.devices.list(page: -1) }.to raise_error(ArgumentError, /from 0/)
      expect(WebMock).not_to have_requested(:get, /devices/)
    end

    it "refuses an unknown order before any request" do
      expect { client.escalations.list(order: :sideways) }.to raise_error(ArgumentError, /asc/)
      expect(WebMock).not_to have_requested(:get, /escalations/)
    end
  end

  describe "list_all" do
    it "walks every page" do
      requests = capture_requests(
        :get,
        "/groups",
        page_of([{ "type" => "team", "id" => "1" }, { "type" => "team", "id" => "2" }], last: false),
        page_of([{ "type" => "team", "id" => "3" }], number: 1, last: true)
      )

      ids = client.groups.list_all(group_type: "team").map(&:id)

      expect(ids).to eq(%w[1 2 3])
      expect(requests.map { |request| request.uri.query_values["pageNumber"] }).to eq(%w[0 1])
      expect(requests.map { |request| request.uri.query_values["type"] }).to eq(%w[team team])
    end

    it "stops on an empty page even when it is not marked last" do
      requests = capture_requests(:get, "/events", page_of([], last: false))

      expect(client.events.list_all.to_a).to eq([])
      expect(requests.size).to eq(1)
    end

    it "fetches nothing until it is iterated, and only as many pages as it needs" do
      requests = capture_requests(
        :get,
        "/devices",
        page_of([{ "fingerprint" => "a" }, { "fingerprint" => "b" }], last: false),
        page_of([{ "fingerprint" => "c" }], number: 1)
      )

      devices = client.devices.list_all

      expect(requests).to be_empty
      expect(devices.first(2).map(&:fingerprint)).to eq(%w[a b])
      expect(requests.size).to eq(1)
    end

    it "yields to a block when given one" do
      capture_requests(
        :get,
        "/devices",
        page_of([{ "fingerprint" => "a" }], last: false),
        page_of([{ "fingerprint" => "b" }], number: 1)
      )

      fingerprints = []

      expect(client.devices.list_all { |device| fingerprints << device.fingerprint }).to be_nil
      expect(fingerprints).to eq(%w[a b])
    end

    it "refuses a bad argument when called, not when iterated" do
      expect { client.escalations.list_all(status: :snoozed) }.to raise_error(ArgumentError, /acknowledged/)
    end
  end

  describe Dregs::Page do
    it "treats a response that is not a page as one empty last page" do
      page = described_class.from_api("nonsense", Dregs::Identity)

      expect(page).to be_empty
      expect(page.last?).to be(true)
      expect(page.has_next?).to be(false)
      expect(page.total_elements).to eq(0)
    end

    it "skips items that are not objects" do
      payload = { "content" => [{ "id" => "a" }, "b", nil], "last" => true }

      page = described_class.from_api(payload, Dregs::Identity)

      expect(page.map(&:id)).to eq(["a"])
    end

    it "returns an enumerator when each is called without a block" do
      expect(described_class.new.each).to be_a(Enumerator)
    end
  end
end
