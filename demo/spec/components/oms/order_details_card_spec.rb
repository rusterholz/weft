# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderDetailsCard, type: :component do
  let(:order) do
    Oms::Order.create!(customer_name: "Acme Corp", city: "Portland",
                       address_line_1: "1 Main St", # rubocop:disable Naming/VariableNumber
                       state: "OR", zip: "97201", lat: 0.0, lon: 0.0, status: "submitted")
  end

  it "renders the order's customer, address, and creation time" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_details_card }
    expect(html).to include("Acme Corp")
    expect(html).to include("1 Main St, Portland, OR, 97201")
    expect(html).to include(order.created_at.strftime("%Y-%m-%d"))
  end

  it "titles itself Details" do
    html = render_weft_html({ order: order }, wire: { "order_id" => order.id }) { order_details_card }
    expect(html).to include("Details")
  end

  it "sets a convention-based DOM ID so it can be swapped out of band" do
    component = render_weft({ order: order }, wire: { "order_id" => order.id }) { order_details_card }
    expect(component.id).to eq("oms-order-details-card-#{order.id}")
  end

  it "derives the order on its own when nothing hands one down" do
    html = render_weft_html({}, wire: { "order_id" => order.id }) { order_details_card }
    expect(html).to include("Acme Corp")
  end
end
