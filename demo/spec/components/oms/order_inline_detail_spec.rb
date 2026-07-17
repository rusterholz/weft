# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderInlineDetail, type: :component do
  let(:order) do
    o = Oms::Order.create!(customer_name: "Test Customer", lat: 0.0, lon: 0.0,
                           address_line_1: "123 Main", city: "SF", state: "CA", zip: "94102") # rubocop:disable Naming/VariableNumber
    Oms::LineItem.create!(order: o, item_type: "widget", quantity: 3)
    o
  end

  it "renders as a tr element" do
    o = order
    component = render_weft(wire: { "order_id" => o.id }) { order_inline_detail }

    expect(component.tag_name).to eq("tr")
  end

  it "includes a dismiss close button with htmx delete" do
    o = order
    html = render_weft_html(wire: { "order_id" => o.id }) { order_inline_detail }

    expect(html).to include('hx-delete="/_components/oms/order_inline_detail/close"')
    expect(html).to include('hx-swap="delete"')
  end

  it "displays order details" do
    o = order
    html = render_weft_html(wire: { "order_id" => o.id }) { order_inline_detail }

    expect(html).to include("Test Customer")
    expect(html).to include("123 Main")
    expect(html).to include("widget (3)")
  end

  it "shows shipments when they exist" do
    o = order
    warehouse = Logistics::Warehouse.create!(name: "W1", lat: 0.0, lon: 0.0)
    shipment = Logistics::Shipment.create!(order_id: o.id, warehouse: warehouse, status: "planned")

    html = render_weft_html(wire: { "order_id" => o.id }) { order_inline_detail }

    expect(html).to include(shipment.id[..7])
  end
end
