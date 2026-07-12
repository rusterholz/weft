# frozen_string_literal: true

require "spec_helper"

RSpec.describe Simulation::Restock do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  it "restocks items with quantity <= 0" do
    depleted = Logistics::StockItem.create!(warehouse: warehouse, item_type: "wireless-mouse", quantity: 0)
    negative = Logistics::StockItem.create!(warehouse: warehouse, item_type: "usb-c-hub", quantity: -1)
    healthy  = Logistics::StockItem.create!(warehouse: warehouse, item_type: "laptop-stand", quantity: 5)

    described_class.call

    expect(depleted.reload.quantity).to eq(10)
    expect(negative.reload.quantity).to eq(10)
    expect(healthy.reload.quantity).to eq(5)
  end
end
