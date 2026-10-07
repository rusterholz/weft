# frozen_string_literal: true

require "weft/request"
require "weft/request/event_frame"

RSpec.describe Weft::Request::EventFrame do
  let(:request) { Weft::Request.wrap(nil) }

  it "carries the request it answers" do
    expect(described_class.new(request).request).to be(request)
  end

  describe "#slots" do
    it "starts as an empty register" do
      expect(described_class.new(request).slots).to eq(Set.new)
    end

    it "is a register of the frame's own, never another frame's" do
      first, second = Array.new(2) { described_class.new(request) }

      expect(first.slots).not_to be(second.slots)
    end
  end
end
