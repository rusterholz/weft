# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::PrepareOrder do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  let(:items) { %w[wireless-mouse usb-c-hub] }

  let(:order) do
    o = Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0)
    items.each { |t| Oms::LineItem.create!(order: o, item_type: t, quantity: 1) }
    o
  end

  before do
    items.each do |item_type|
      Logistics::StockItem.create!(warehouse: warehouse, item_type: item_type, quantity: 10)
    end
  end

  it "creates shipments from a submitted order" do
    described_class.call(order)

    shipments = Logistics::Shipment.for_order(order.id)
    expect(shipments.size).to eq(1)
    expect(shipments.first.warehouse_id).to eq(warehouse.id)
    expect(shipments.first.status).to eq("planned")
  end

  it "moves the order to processing" do
    described_class.call(order)

    expect(order.reload.status).to eq("processing")
  end

  it "decrements warehouse stock" do
    described_class.call(order)

    items.each do |item_type|
      stock = Logistics::StockItem.find_by!(warehouse: warehouse, item_type: item_type)
      expect(stock.quantity).to eq(9)
    end
  end

  it "does nothing if the order is not submitted" do
    order.update!(status: "processing")

    described_class.call(order)

    expect(Logistics::Shipment.count).to eq(0)
    expect(order.reload.status).to eq("processing")
  end

  it "does nothing if no warehouse has stock" do
    Logistics::StockItem.update_all(quantity: 0)

    described_class.call(order)

    expect(Logistics::Shipment.count).to eq(0)
    expect(order.reload.status).to eq("submitted")
  end
end
