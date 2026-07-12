# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrdersPage, type: :component do
  before do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0, status: "submitted")
    Oms::Order.create!(customer_name: "Bob", lat: 0.0, lon: 0.0, status: "shipped")
  end

  it "auto-routes at /orders" do
    expect(described_class.page_path).to eq("/orders")
    expect(described_class).to be_routable
  end

  def rendered(attrs = {})
    klass = described_class
    render_weft_html { insert_tag(klass, **attrs) }
  end

  it "renders the Orders heading and a New Order link" do
    html = rendered
    expect(html).to include("Orders")
    expect(html).to include('href="/orders/new"')
  end

  it "shows all orders by default" do
    html = rendered
    expect(html).to include("Alice")
    expect(html).to include("Bob")
  end

  it "passes the status filter through to orders_panel" do
    html = rendered(status: "submitted")
    expect(html).to include("Alice")
    expect(html).not_to include("Bob")
    expect(html).to include("Submitted Orders")
  end
end
