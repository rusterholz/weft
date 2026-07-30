# frozen_string_literal: true

require "spec_helper"

RSpec.describe DrillsPage, type: :component do
  def rendered
    klass = described_class
    render_weft_html { insert_tag(klass) }
  end

  it "auto-routes at /drills" do
    expect(described_class.page_path).to eq("/drills")
    expect(described_class).to be_routable
  end

  it "renders cleanly — failing drills are click-loaded, never embedded" do
    expect(rendered).to include("Error drills")
  end

  it "links the three bogus-id branded-404 drills" do
    html = rendered
    expect(html).to include('href="/orders/no-such-order"')
    expect(html).to include('href="/shipments/no-such-shipment"')
    expect(html).to include('href="/drivers/no-such-driver"')
  end

  it "links the routing-miss drill" do
    expect(rendered).to include('href="/no-such-path"')
  end

  it "links the validation drill at the order form" do
    expect(rendered).to include('href="/orders/new"')
  end

  it "renders a click-to-load trigger for the component-failure drill" do
    expect(rendered).to include('hx-get="/_components/drills/boom"')
  end

  it "links the page-failure drill" do
    expect(rendered).to include('href="/drills/boom"')
  end

  it "renders a click-to-load trigger for the redirect-recovery drill" do
    expect(rendered).to include('hx-get="/_components/drills/redirect_boom"')
  end

  it "embeds the destructive-swap drill rows with live delete triggers" do
    expect(rendered).to include('hx-delete="/_components/drills/boom_row/remove"')
  end

  it "links a live order for the stream-outage drill when shipments exist" do
    warehouse = Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0)
    order = Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0)
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "in_transit")

    expect(rendered).to include(%(href="/orders/#{order.id}"))
  end

  it "explains itself when no shipments exist yet for the stream-outage drill" do
    expect(rendered).to include("simulator")
  end
end
