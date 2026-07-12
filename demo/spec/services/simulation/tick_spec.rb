# frozen_string_literal: true

require "spec_helper"

RSpec.describe Simulation::Tick do
  let(:warehouse) do
    Logistics::Warehouse.create!(name: "Test WH", lat: 1.0, lon: 1.0)
  end

  before do
    # Stock the warehouse so PrepareOrder can plan shipments
    %w[wireless-mouse usb-c-hub].each do |item_type|
      Logistics::StockItem.create!(warehouse: warehouse, item_type: item_type, quantity: 20)
    end

    # A driver so DispatchShipment can assign one
    Delivery::Driver.create!(name: "Driver", total_mileage: 0.0)

    # Seed a submitted order with line items
    order = Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "submitted")
    %w[wireless-mouse usb-c-hub].each do |item_type|
      Oms::LineItem.create!(order: order, item_type: item_type, quantity: 1)
    end
  end

  it "advances entities through lifecycle stages" do
    # Tick 1: submitted -> processing (PrepareOrder creates shipments)
    described_class.call
    order = Oms::Order.first
    expect(order.status).to eq("processing")
    expect(Logistics::Shipment.for_order(order.id).count).to be >= 1

    # Tick 2: planned -> packed, processing -> shipped
    described_class.call
    expect(Logistics::Shipment.for_order(order.id)).to all(have_attributes(status: "packed"))
    expect(order.reload.status).to eq("shipped")

    # Tick 3: packed -> in_transit
    described_class.call
    expect(Logistics::Shipment.for_order(order.id)).to all(have_attributes(status: "in_transit"))

    # Tick 4: in_transit -> delivered, shipped -> fulfilled
    described_class.call
    expect(Logistics::Shipment.for_order(order.id)).to all(have_attributes(status: "delivered"))
    expect(order.reload.status).to eq("fulfilled")
  end
end
