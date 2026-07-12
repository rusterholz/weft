# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::RecentOrdersCard, type: :component do
  it "renders recent orders inside a content card" do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "submitted")
    html = render_weft_html { recent_orders_card }
    expect(html).to include("Recent Orders")
    expect(html).to include("Alice")
  end

  it "includes auto-generated refresh attributes" do
    html = render_weft_html { recent_orders_card }
    expect(html).to include('hx-trigger="every 10s"')
    expect(html).to include('hx-get="/_components/oms/recent_orders_card"')
    expect(html).to include('hx-swap="outerHTML"')
  end
end
