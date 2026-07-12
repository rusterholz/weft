# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderHeader, type: :component do
  let(:order) { Oms::Order.create!(customer_name: "Test Customer", lat: 0.0, lon: 0.0, status: "submitted") }

  it "renders order ID and status badge" do
    html = render_weft_html(order: order) { order_header(order_id: order.id) }
    expect(html).to include(order.id[..7])
    expect(html).to include("badge-submitted")
  end

  it "renders the force-advance button with htmx attributes" do
    html = render_weft_html(order: order) { order_header(order_id: order.id) }
    expect(html).to include("Force Advance")
    expect(html).to include('hx-post="/_components/oms/order_header/advance"')
    expect(html).to include("hx-target")
    expect(html).to include('hx-swap="outerHTML"')
  end

  it "hides the advance button when fulfilled" do
    order.update!(status: "fulfilled")
    html = render_weft_html(order: order) { order_header(order_id: order.id) }
    expect(html).not_to include("Force Advance")
  end

  it "sets a convention-based DOM ID" do
    component = render_weft(order: order) { order_header(order_id: order.id) }
    expect(component.id).to eq("oms-order-header-#{order.id}")
  end
end
