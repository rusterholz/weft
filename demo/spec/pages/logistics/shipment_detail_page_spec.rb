# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentDetailPage, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0) }
  let(:shipment) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "in_transit",
      items: [{ "type" => "widget", "qty" => 2 }]
    )
  end

  it "auto-routes at /shipments/:shipment_id" do
    expect(described_class.page_path).to eq("/shipments/:shipment_id")
    expect(described_class).to be_routable
  end

  def rendered
    klass = described_class
    id = shipment.id
    render_weft_html { insert_tag(klass, shipment_id: id) }
  end

  it "renders shipment details and the linked order" do
    html = rendered
    expect(html).to include(shipment.id[..7])
    expect(html).to include("Main WH")
    expect(html).to include(order.id[..7])
  end

  it "renders the items table" do
    html = rendered
    expect(html).to include("Items (1)")
    expect(html).to include("widget")
  end
end
