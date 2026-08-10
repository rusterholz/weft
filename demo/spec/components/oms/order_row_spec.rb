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
    expect(html).to include('hx-trigger="click once"')
    expect(html).to include('hx-target="closest tr"')
  end

  it "derives a unique DOM id from the handed-off order id" do
    html = render_weft_html({ order: order }) { order_row order_id: order.id, order: order }
    expect(html).to include("id=\"oms-order-row-#{order.id}\"")
  end

  it "wires a cancel dismissal with a browser confirm" do
    html = render_weft_html({ order: order }) { order_row order_id: order.id, order: order }
    expect(html).to include('hx-delete="/_components/oms/order_row/cancel"')
    expect(html).to include('hx-swap="delete"')
    expect(html).to include("hx-confirm=")
  end

  it "destroys the order when the cancel action runs" do
    run_action(described_class, :cancel, :delete, order_id: order.id)

    expect(Oms::Order.exists?(order.id)).to be(false)
  end

  it "renders standalone from the wire, deriving the order itself" do
    html = render_weft_html(wire: { order_id: order.id }) { order_row }
    expect(html).to include("Alice Smith")
  end
end
