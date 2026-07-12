# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::DispatchShipment do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "shipped")
  end

  let!(:shipment) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "packed",
      items: [{ type: "wireless-mouse", qty: 1 }]
    )
  end

  let!(:low_mileage_driver) do
    Delivery::Driver.create!(name: "Lo", total_mileage: 10.0)
  end

  let!(:high_mileage_driver) do
    Delivery::Driver.create!(name: "Hi", total_mileage: 500.0)
  end

  it "moves the shipment from packed to in_transit" do
    described_class.call(shipment)

    expect(shipment.reload.status).to eq("in_transit")
  end

  it "assigns the lowest-mileage available driver" do
    described_class.call(shipment)

    expect(shipment.reload.driver_id).to eq(low_mileage_driver.id)
  end

  it "sets the driver's current_shipment_id" do
    described_class.call(shipment)

    expect(low_mileage_driver.reload.current_shipment_id).to eq(shipment.id)
  end

  it "does nothing if no drivers are available" do
    Delivery::Driver.update_all(current_shipment_id: "some-shipment")

    described_class.call(shipment)

    expect(shipment.reload.status).to eq("packed")
  end

  it "does nothing if the shipment is not packed" do
    shipment.update!(status: "planned")

    described_class.call(shipment)

    expect(shipment.reload.status).to eq("planned")
  end
end
