# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentsPage, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Test", lat: 1.0, lon: 1.0) }

  before do
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned")
  end

  it "auto-routes at /shipments" do
    expect(described_class.page_path).to eq("/shipments")
    expect(described_class).to be_routable
  end

  def rendered(attrs = {})
    klass = described_class
    render_weft_html { insert_tag(klass, **attrs) }
  end

  it "renders the Shipments heading" do
    expect(rendered).to include("Shipments")
  end

  it "renders the shipments panel content" do
    expect(rendered).to include("All Shipments")
    expect(rendered).to include("Main WH")
  end
end
