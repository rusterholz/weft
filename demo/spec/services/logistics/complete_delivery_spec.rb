# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::CompleteDelivery do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "shipped")
  end

  let(:driver) do
    Delivery::Driver.create!(name: "Driver", total_mileage: 100.0)
  end

  let!(:shipment) do
    s = Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "in_transit",
      driver_id: driver.id, items: [{ type: "wireless-mouse", qty: 1 }]
    )
    driver.update!(current_shipment_id: s.id)
    s
  end

  it "moves the shipment from in_transit to delivered" do
    described_class.call(shipment)

    expect(shipment.reload.status).to eq("delivered")
  end

  it "releases the driver by clearing current_shipment_id" do
    described_class.call(shipment)

    expect(driver.reload.current_shipment_id).to be_nil
  end

  it "adds mileage to the driver" do
    described_class.call(shipment)

    expect(driver.reload.total_mileage).to be > 100.0
  end

  it "calls FulfillOrder on the associated order" do
    # Only shipment for this order, so fulfillment should trigger
    described_class.call(shipment)

    expect(order.reload.status).to eq("fulfilled")
  end

  it "does nothing if the shipment is not in_transit" do
    shipment.update!(status: "packed")

    described_class.call(shipment)

    expect(shipment.reload.status).to eq("packed")
    expect(driver.reload.current_shipment_id).to eq(shipment.id)
  end
end
