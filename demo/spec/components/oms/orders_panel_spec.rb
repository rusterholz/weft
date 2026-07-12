# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrdersPanel, type: :component do
  before do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "submitted")
    Oms::Order.create!(customer_name: "Bob", lat: 0.0, lon: 0.0, status: "shipped")
  end

  it "renders filter buttons with performs actions" do
    html = render_weft_html { orders_panel }
    expect(html).to include("All")
    expect(html).to include("Submitted")
    expect(html).to include('hx-get="/_components/oms/orders_panel/submitted"')
    expect(html).to include('hx-get="/_components/oms/orders_panel/all"')
  end

  it "marks the active filter" do
    html = render_weft_html { orders_panel(status: "shipped") }
    expect(html).to include("Shipped Orders")
    # The "Shipped" button should be btn-primary (active)
    expect(html).to match(/btn-primary[^>]*>Shipped/)
  end

  it "renders all orders when no status filter" do
    html = render_weft_html { orders_panel }
    expect(html).to include("Alice")
    expect(html).to include("Bob")
    expect(html).to include("All Orders (2)")
  end

  it "filters orders by status" do
    html = render_weft_html { orders_panel(status: "submitted") }
    expect(html).to include("Alice")
    expect(html).not_to include("Bob")
    expect(html).to include("Submitted Orders (1)")
  end

  it "includes hx-push-url on filter buttons for user-friendly URLs" do
    html = render_weft_html { orders_panel }
    expect(html).to include('hx-push-url="/orders?status=submitted"')
    expect(html).to include('hx-push-url="/orders"')
  end

  it "renders pagination for large result sets" do
    28.times { |i| Oms::Order.create!(customer_name: "Order#{i}", lat: 0.0, lon: 0.0, status: "submitted") }
    html = render_weft_html { orders_panel(status: "submitted") }
    expect(html).to include("Page 1 of 2")
    expect(html).to include("Next")
  end
end
