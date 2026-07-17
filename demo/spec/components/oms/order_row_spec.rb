# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderRow, type: :component do
  let(:order) do
    o = Oms::Order.create!(customer_name: "Alice Smith", lat: 1.0, lon: 1.0)
    Oms::LineItem.create!(order: o, item_type: "widget", quantity: 2)
    o
  end

  it "renders as a tr" do
    component = render_arbre(order: order) { order_row order: order }
    expect(component.tag_name).to eq("tr")
  end

  it "shows a truncated order ID linking to the order" do
    html = render_arbre_html(order: order) { order_row order: order }
    expect(html).to include(order.id[..7])
    expect(html).to include("href=\"/orders/#{order.id}\"")
  end

  it "shows the customer name" do
    html = render_arbre_html(order: order) { order_row order: order }
    expect(html).to include("Alice Smith")
  end

  it "shows a status badge" do
    html = render_arbre_html(order: order) { order_row order: order }
    expect(html).to include("badge-submitted")
  end

  it "shows line item count" do
    html = render_arbre_html(order: order) { order_row order: order }
    expect(html).to include("<td class=\"mono\">1</td>")
  end

  it "includes an inline expand button wired via the inline_expand: preset" do
    html = render_weft_html({ order: order }) { order_row order: order }
    expect(html).to include("hx-get=\"/_components/oms/order_inline_detail?order_id=#{order.id}\"")
    expect(html).to include('hx-swap="afterend"')
    expect(html).to include('hx-trigger="click"')
    expect(html).to include('hx-target="closest tr"')
  end
end
