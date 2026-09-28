# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentRow, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Test", lat: 1.0, lon: 1.0) }

  let(:shipment) do
    Logistics::Shipment.create!(
      order_id: order.id,
      warehouse: warehouse,
      status: "planned",
      items: [{ "item_type" => "widget", "qty" => 3 }]
    )
  end

  it "renders as a tr" do
    record = shipment
    component = render_weft { shipment_row shipment: record }
    expect(component.tag_name).to eq("tr")
  end

  it "shows a truncated shipment ID" do
    record = shipment
    html = render_weft_html { shipment_row shipment: record }
    expect(html).to include(shipment.id[..7])
    expect(html).to include("href=\"/shipments/#{shipment.id}\"")
  end

  it "shows the warehouse name" do
    record = shipment
    html = render_weft_html { shipment_row shipment: record }
    expect(html).to include("Main WH")
  end

  it "shows a status badge" do
    record = shipment
    html = render_weft_html { shipment_row shipment: record }
    expect(html).to include("badge-planned")
  end

  it "shows a dash when no driver is assigned" do
    record = shipment
    html = render_weft_html { shipment_row shipment: record }
    expect(html).to include("\u2014")
  end

  it "shows the driver name when assigned" do
    driver = Delivery::Driver.create!(name: "Bob")
    shipment.update!(driver_id: driver.id)
    record = shipment
    html = render_weft_html { shipment_row shipment: record }
    expect(html).to include("Bob")
  end
end
