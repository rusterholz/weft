# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentDetailPage, type: :component do
  let(:warehouse) { Logistics::Warehouse.create!(name: "Main WH", lat: 1.0, lon: 1.0) }
  let(:order) { Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0) }
  let(:shipment) do
    Logistics::Shipment.create!(
      order_id: order.id, warehouse: warehouse, status: "in_transit",
      items: [{ "type" => "widget", "qty" => 2 }]
    )
  end

  it "auto-routes at /shipments/:shipment_id" do
    expect(described_class.page_path).to eq("/shipments/:shipment_id")
    expect(described_class).to be_routable
  end

  # A well-formed uuid that addresses nothing. It has to be well-formed to
  # reach the lookup at all: `type: :uuid` refuses a value that is not a uuid
  # before any query happens, which is the separate claim below.
  it "raises ActiveRecord::RecordNotFound for a well-formed id matching no shipment" do
    klass = described_class
    expect do
      render_weft_html(wire: { "shipment_id" => "00000000-0000-4000-8000-000000000000" }) { insert_tag(klass) }
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  # The other half, and a different failure entirely: this one never reaches
  # the database. "not a uuid" and "a uuid nobody has" are distinct answers,
  # and conflating them sends an unreadable request to the lookup to find out.
  it "refuses an id that is not a uuid at all, before any lookup" do
    klass = described_class
    expect do
      render_weft_html(wire: { "shipment_id" => "wombat" }) { insert_tag(klass) }
    end.to raise_error(Weft::InvalidParamValue, /wombat/)
  end

  def rendered
    klass = described_class
    id = shipment.id
    render_weft_html(wire: { "shipment_id" => id }) { insert_tag(klass) }
  end

  it "renders shipment details and the linked order" do
    html = rendered
    expect(html).to include(shipment.id[..7])
    expect(html).to include("Main WH")
    expect(html).to include(order.id[..7])
  end

  it "renders the items table" do
    html = rendered
    expect(html).to include("Items (1)")
    expect(html).to include("widget")
  end
end
