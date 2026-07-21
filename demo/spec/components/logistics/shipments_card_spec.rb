# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentsCard, type: :component do
  let(:order) do
    Oms::Order.create!(customer_name: "Test", lat: 0.0, lon: 0.0, status: "processing")
  end

  it "renders with SSE push attributes" do
    o = order
    html = render_weft_html(wire: { "order_id" => o.id }) { shipments_card }

    expect(html).to include('hx-ext="sse"')
    expect(html).to include("sse-connect=\"/_components/logistics/shipments_card/_stream?order_id=#{o.id}\"")
    expect(html).to include("sse-swap=\"logistics-shipments-card-#{o.id}\"")
    expect(html).to include('hx-swap="innerHTML"')
  end

  it "renders shipments inside a content card" do
    o = order
    warehouse = Logistics::Warehouse.create!(name: "W1", lat: 0.0, lon: 0.0)
    Logistics::Shipment.create!(order_id: o.id, warehouse: warehouse, status: "planned")

    html = render_weft_html(wire: { "order_id" => o.id }) { shipments_card }

    expect(html).to include("Shipments (1)")
  end

  it "shows empty table when no shipments exist" do
    o = order
    html = render_weft_html(wire: { "order_id" => o.id }) { shipments_card }

    expect(html).to include("Shipments (0)")
  end

  it "derives its title into the card header, not onto the wrapper" do
    o = order
    html = render_weft_html(wire: { "order_id" => o.id }) { shipments_card }

    expect(html).to include("<h2>Shipments (0)</h2>")
    expect(html).not_to include('title="Shipments')
  end

  it "declares includes Oms::OrderHeader for OOB swap" do
    inclusions = described_class.inclusions
    expect(inclusions.size).to eq(1)
    expect(inclusions.first[:component_class]).to eq(Oms::OrderHeader)
  end
end
