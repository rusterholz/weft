# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentFeedOutage do
  after { described_class.toggle! if described_class.active? }

  it "starts inactive and passes check!" do
    expect(described_class.active?).to be(false)
    expect { described_class.check! }.not_to raise_error
  end

  it "raises FeedUnavailable from check! while active" do
    described_class.toggle!

    expect(described_class.active?).to be(true)
    expect { described_class.check! }.
      to raise_error(described_class::FeedUnavailable, /simulated outage/)
  end

  it "toggles back off" do
    described_class.toggle!
    described_class.toggle!

    expect(described_class.active?).to be(false)
  end
end
