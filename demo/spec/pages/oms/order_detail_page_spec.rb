# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderDetailPage, type: :component do
  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0,
                       city: "Springfield", state: "CA", zip: "90210")
  end

  before do
    Oms::LineItem.create!(order: order, item_type: "widget", quantity: 3)
  end

  it "auto-routes at /orders/:order_id" do
    expect(described_class.page_path).to eq("/orders/:order_id")
    expect(described_class).to be_routable
  end

  def rendered
    klass = described_class
    id = order.id
    render_weft_html { insert_tag(klass, order_id: id) }
  end

  it "renders the order header and customer details" do
    html = rendered
    expect(html).to include(order.id[..7])
    expect(html).to include("Alice")
    expect(html).to include("Springfield")
  end

  it "renders the line items table" do
    html = rendered
    expect(html).to include("Line Items (1)")
    expect(html).to include("widget")
    expect(html).to match(/<td[^>]*>3</)
  end
end
