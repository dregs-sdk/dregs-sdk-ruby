# frozen_string_literal: true

RSpec.describe "the models" do
  describe Dregs::Category do
    it "parses the API's upper-case spelling" do
      expect(described_class.parse("HUMANITY")).to eq(:humanity)
    end

    it "parses a lower-case spelling too" do
      expect(described_class.parse("behavior")).to eq(:behavior)
    end

    it "parses a symbol" do
      expect(described_class.parse(:AUTHENTICITY)).to eq(:authenticity)
    end

    it "returns nil for a category this release predates" do
      expect(described_class.parse("REPUTATION")).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.parse(nil)).to be_nil
    end

    it "lists the four categories" do
      expect(described_class::ALL).to eq(%i[humanity authenticity uniqueness behavior])
    end
  end

  describe Dregs::Scores do
    subject(:scores) do
      described_class.from_api(
        [
          { "category" => "HUMANITY", "value" => 85 },
          { "category" => "BEHAVIOR", "value" => 68 }
        ]
      )
    end

    it "sums through Enumerable" do
      expect(scores.sum(&:value)).to eq(153)
    end

    it "sorts through Enumerable" do
      expect(scores.min_by(&:value).category).to eq(:behavior)
    end

    it "reports its length" do
      expect(scores.length).to eq(2)
    end

    it "returns an enumerator when each is called without a block" do
      expect(scores.each).to be_a(Enumerator)
    end

    it "is empty when built from nothing" do
      expect(described_class.new).to be_empty
    end

    it "is empty when the response was not an array" do
      expect(described_class.from_api(nil)).to be_empty
    end
  end

  describe Dregs::TrackResult do
    it "counts an id as acceptance" do
      expect(described_class.from_api({ "id" => "evt_1" }).accepted?).to be(true)
    end

    it "counts a missing id as a quiet rejection" do
      expect(described_class.from_api({ "status" => "success" }).accepted?).to be(false)
    end

    it "tolerates a body that is not a hash" do
      expect(described_class.from_api(nil).accepted?).to be(false)
    end
  end

  describe Dregs::Analysis do
    it "has empty scores when the response carried none" do
      expect(described_class.from_api({ "id" => 1 }).observations).to eq([])
    end
  end
end
