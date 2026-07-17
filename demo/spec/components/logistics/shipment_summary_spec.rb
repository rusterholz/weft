# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentSummary, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }

  it "renders an error message when the order is missing" do
    shipment = Logistics::Shipment.create!(order_id: "missing", warehouse: warehouse, status: "planned")
    html = render_weft_html(wire: { "shipment_id" => shipment.id }) { shipment_summary }
    expect(html).to include("Order not found.")
  end

  it "renders order details when the order exists" do
    order = Oms::Order.create!(customer_name: "Alice", lat: 1.0, lon: 1.0, city: "Portland", state: "OR")
    shipment = Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "in_transit",
      items: [{ "type" => "widget", "qty" => 2 }]
    )
    html = render_weft_html(wire: { "shipment_id" => shipment.id }) { shipment_summary }
    expect(html).to include(order.id[..7])
    expect(html).to include("Alice")
    expect(html).to include("Portland, OR")
    expect(html).to include("widget (2)")
  end
end
