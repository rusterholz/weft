# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::NewOrderPage, type: :component do
  it "auto-routes at /orders/new" do
    expect(described_class.page_path).to eq("/orders/new")
    expect(described_class).to be_routable
  end

  it "renders the page chrome and embeds Oms::OrderForm" do
    html = described_class.render
    expect(html).to include("New Order")
    expect(html).to include("Create Order")
    expect(html).to include('action="/_components/oms/order_form/create"')
  end
end
