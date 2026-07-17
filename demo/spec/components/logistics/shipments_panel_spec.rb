# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentsPanel, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Test", lat: 1.0, lon: 1.0) }

  before do
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned")
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "in_transit")
  end

  it "renders a content card with the shipment count" do
    html = render_weft_html { shipments_panel }
    expect(html).to include("All Shipments (2)")
  end

  it "renders the shipments table with all shipments" do
    html = render_weft_html { shipments_panel }
    expect(html).to include("Main WH")
    expect(html.scan(%r{<tr[^>]*>.*?</tr>}m).size).to be >= 2
  end

  it "renders pagination for large result sets" do
    28.times { Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned") }
    html = render_weft_html { shipments_panel }
    expect(html).to include("Page 1 of 2")
    expect(html).to include("Next")
  end

  it "respects the page param" do
    28.times { Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned") }
    html = render_weft_html(wire: { "page" => 2 }) { shipments_panel }
    expect(html).to include("Page 2 of")
  end
end
