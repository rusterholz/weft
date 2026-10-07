# frozen_string_literal: true

require "weft/request"
require "weft/request/event_frame"

RSpec.describe Weft::Request::EventFrame do
  let(:request) { Weft::Request.wrap(nil) }

  it "carries the request it answers" do
    expect(described_class.new({}, request: request).request).to be(request)
  end

  describe "#universe" do
    it "is everything the client sent, as given" do
      frame = described_class.new({ "status" => "shipped", "undeclared" => "x" }, request: request)

      expect(frame.universe).to eq({ "status" => "shipped", "undeclared" => "x" })
    end

    it "is frozen, since every root in the delivery reads the same one" do
      frame = described_class.new({ "status" => "shipped" }, request: request)

      expect { frame.universe["status"] = "lost" }.to raise_error(FrozenError)
    end

    it "leaves the caller's hash writable" do
      given = { "status" => "shipped" }
      described_class.new(given, request: request)

      expect(given).not_to be_frozen
    end
  end

  describe "#slots" do
    it "starts as an empty register" do
      expect(described_class.new({}, request: request).slots).to eq(Set.new)
    end

    it "is a register of the frame's own, never another frame's" do
      universe = { "status" => "shipped" }.freeze

      first, second = Array.new(2) { described_class.new(universe, request: request) }

      expect(first.slots).not_to be(second.slots)
    end
  end

  it "shares a universe that is already frozen rather than copying it" do
    universe = { "status" => "shipped" }.freeze

    expect(described_class.new(universe, request: request).universe).to be(universe)
  end
end
