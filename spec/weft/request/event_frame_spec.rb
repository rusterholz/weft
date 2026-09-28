# frozen_string_literal: true

require "weft/request/event_frame"

RSpec.describe Weft::Request::EventFrame do
  describe "#universe" do
    it "is everything the client sent, as given" do
      frame = described_class.new({ "status" => "shipped", "undeclared" => "x" })

      expect(frame.universe).to eq({ "status" => "shipped", "undeclared" => "x" })
    end

    it "is frozen, since every root in the delivery reads the same one" do
      frame = described_class.new({ "status" => "shipped" })

      expect { frame.universe["status"] = "lost" }.to raise_error(FrozenError)
    end

    it "leaves the caller's hash writable" do
      given = { "status" => "shipped" }
      described_class.new(given)

      expect(given).not_to be_frozen
    end
  end

  describe "#slots" do
    it "is absent on a delivery with nothing to arbitrate" do
      expect(described_class.new({}).slots).to be_nil
    end

    it "is an empty register on an arbitrated delivery" do
      expect(described_class.new({}, arbitrated: true).slots).to eq(Set.new)
    end
  end

  it "shares a universe that is already frozen rather than copying it" do
    universe = { "status" => "shipped" }.freeze

    expect(described_class.new(universe, arbitrated: true).universe).to be(universe)
  end
end
