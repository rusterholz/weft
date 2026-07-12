# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentManifest, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Test", lat: 1.0, lon: 1.0) }

  it "renders an empty-state message when there are no items" do
    shipment = Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned", items: [])
    html = render_weft_html { shipment_manifest(shipment_id: shipment.id) }
    expect(html).to include("No items in this shipment.")
  end

  it "renders a dl of item types and quantities" do
    shipment = Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "planned",
      items: [{ "type" => "widget", "qty" => 3 }, { "type" => "gadget", "qty" => 1 }]
    )
    html = render_weft_html { shipment_manifest(shipment_id: shipment.id) }
    expect(html).to include("widget")
    expect(html).to include("gadget")
    expect(html).to match(/×\s*3/)
    expect(html).to match(/×\s*1/)
  end
end
