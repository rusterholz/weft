# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderTable, type: :component do
  let(:orders) do
    2.times.map { |i| Oms::Order.create!(customer_name: "Customer #{i}", lat: 1.0, lon: 1.0) }
  end

  it "renders as a table" do
    component = render_arbre { order_table orders: [] }
    expect(component.tag_name).to eq("table")
  end

  it "has the correct column headers" do
    html = render_arbre_html { order_table orders: [] }
    %w[Order Customer Items Shipments Status Created].each do |header|
      expect(html).to include("<th>#{header}</th>")
    end
  end

  it "renders an Oms::OrderRow for each order" do
    html = render_arbre_html(orders: orders) { order_table orders: orders }
    orders.each do |order|
      expect(html).to include(order.id[..7])
    end
  end
end
