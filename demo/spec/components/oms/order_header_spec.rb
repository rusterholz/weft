# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderHeader, type: :component do
  let(:order) { Oms::Order.create!(customer_name: "Test Customer", lat: 0.0, lon: 0.0, status: "submitted") }

  it "renders order ID and status badge" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(html).to include(order.id[..7])
    expect(html).to include("badge-submitted")
  end

  it "renders the force-advance button with htmx attributes" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(html).to include("Force Advance")
    expect(html).to include('hx-post="/_components/oms/order_header/advance"')
    expect(html).to include("hx-target")
    expect(html).to include('hx-swap="outerHTML"')
  end

  it "hides the advance button when fulfilled" do
    order.update!(status: "fulfilled")
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(html).not_to include("Force Advance")
  end

  it "sets a convention-based DOM ID" do
    component = render_weft({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(component.id).to eq("oms-order-header-#{order.id}")
  end

  it "names the customer alongside the order id" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(html).to include("Test Customer")
  end

  it "offers an edit affordance wired to the transfer" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_header }
    expect(html).to include("Edit")
    expect(html).to include('hx-post="/_components/oms/order_header/edit"')
  end

  it "hands the region to the editable header" do
    expect(described_class.actions[%i[edit post]].renders).to eq(Oms::EditableOrderHeader)
  end

  it "opens the editor without a callable — nothing changes on the server" do
    expect(described_class.actions[%i[edit post]].callable).to be_nil
  end

  it "refreshes the shipments card on its own advance, and the details card on an edit arrival" do
    by_class = described_class.inclusions.to_h { |inc| [inc[:component_class], inc] }

    expect(by_class[Logistics::ShipmentsCard][:on]).to eq([:advance])
    expect(by_class[Logistics::ShipmentsCard][:when]).to be_nil
    expect(by_class[Oms::OrderDetailsCard][:when]).to eq([:transferred])
    expect(by_class[Oms::OrderDetailsCard][:on]).to be_nil
  end

  it "stays silent on the wire until per-action triggers exist" do
    expect(described_class.trigger_events).to be_empty
  end
end
