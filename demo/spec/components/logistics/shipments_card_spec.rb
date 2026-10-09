# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentsCard, type: :component do
  let(:order) do
    Oms::Order.create!(customer_name: "Test", lat: 0.0, lon: 0.0, status: "processing")
  end

  def render_card = described_class.render({ order_id: order.id }, nil)

  it "renders with SSE push attributes" do
    html = render_card

    expect(html).to include('hx-ext="sse"')
    expect(html).to include("sse-connect=\"/_components/logistics/shipments_card/_stream?order_id=#{order.id}\"")
    expect(html).to include("sse-swap=\"logistics-shipments-card-#{order.id}\"")
    expect(html).to include('sse-close="weft:close"')
    expect(html).to include('hx-swap="innerHTML"')
  end

  it "raises FeedUnavailable while the outage drill is active" do
    Logistics::ShipmentFeedOutage.toggle!

    expect { render_card }.to raise_error(Logistics::ShipmentFeedOutage::FeedUnavailable)
  ensure
    Logistics::ShipmentFeedOutage.toggle! if Logistics::ShipmentFeedOutage.active?
  end

  it "renders shipments inside a content card" do
    warehouse = Logistics::Warehouse.create!(name: "W1", lat: 0.0, lon: 0.0)
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned")

    expect(render_card).to include("Shipments (1)")
  end

  it "shows empty table when no shipments exist" do
    expect(render_card).to include("Shipments (0)")
  end

  it "derives its title into the card header, not onto the wrapper" do
    html = render_card

    expect(html).to include("<h2>Shipments (0)</h2>")
    expect(html).not_to include('title="Shipments')
  end

  it "declares brings Oms::OrderHeader for OOB swap" do
    companions = described_class.companions
    expect(companions.size).to eq(1)
    expect(companions.first[:component_class]).to eq(Oms::OrderHeader)
  end
end
