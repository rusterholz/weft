# frozen_string_literal: true

require "spec_helper"

RSpec.describe Simulation::OrderGenerator do
  it "creates an order with line items" do
    order = described_class.call

    expect(order).to be_a(Oms::Order)
    expect(order).to be_persisted
    expect(order.status).to eq("submitted")
    expect(order.customer_name).to be_present
    expect(order.line_items.size).to be_between(2, 6)
  end
end
