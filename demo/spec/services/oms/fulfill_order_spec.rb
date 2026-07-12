# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::FulfillOrder do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "shipped")
  end

  let!(:shipment_a) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "delivered",
      items: [{ type: "wireless-mouse", qty: 1 }]
    )
  end

  let!(:shipment_b) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "delivered",
      items: [{ type: "usb-c-hub", qty: 1 }]
    )
  end

  it "marks the order fulfilled when all shipments are delivered" do
    described_class.call(order)

    expect(order.reload.status).to eq("fulfilled")
  end

  it "does nothing if the order is not shipped" do
    order.update!(status: "processing")

    described_class.call(order)

    expect(order.reload.status).to eq("processing")
  end

  it "does nothing if some shipments are not delivered" do
    shipment_b.update!(status: "in_transit")

    described_class.call(order)

    expect(order.reload.status).to eq("shipped")
  end
end
