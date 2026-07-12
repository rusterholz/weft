# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::PackShipment do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "processing")
  end

  let!(:shipment) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "planned",
      items: [{ type: "wireless-mouse", qty: 1 }]
    )
  end

  it "moves the shipment from planned to packed" do
    described_class.call(shipment)

    expect(shipment.reload.status).to eq("packed")
  end

  it "moves the order to shipped when all sibling shipments are packed" do
    described_class.call(shipment)

    expect(order.reload.status).to eq("shipped")
  end

  it "does not move the order to shipped when other shipments are still planned" do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "planned",
      items: [{ type: "usb-c-hub", qty: 1 }]
    )

    described_class.call(shipment)

    expect(order.reload.status).to eq("processing")
  end

  it "does nothing if the shipment is not planned" do
    shipment.update!(status: "packed")

    described_class.call(shipment)

    expect(shipment.reload.status).to eq("packed")
  end
end
