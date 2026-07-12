# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderStatusCard, type: :component do
  it "displays the order count for the given status" do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "submitted")
    Oms::Order.create!(customer_name: "Bob", lat: 0.0, lon: 0.0, status: "submitted")
    Oms::Order.create!(customer_name: "Carol", lat: 0.0, lon: 0.0, status: "shipped")

    html = render_weft_html { order_status_card status: "submitted" }

    expect(html).to include("Submitted")
    expect(html).to include(">2<")
  end

  it "renders a stat-card with the matching accent" do
    component = render_weft { order_status_card status: "shipped" }
    expect(component.to_s).to include("border-shipped")
  end

  it "includes auto-generated refresh attributes" do
    html = render_weft_html { order_status_card status: "submitted" }
    expect(html).to include('hx-trigger="every 10s"')
    expect(html).to include('hx-get="/_components/oms/order_status_card?')
    expect(html).to include('hx-swap="outerHTML"')
  end
end
