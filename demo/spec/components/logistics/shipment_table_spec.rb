# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentTable, type: :component do
  it "renders as a table" do
    component = render_weft { shipment_table shipments: [] }
    expect(component.tag_name).to eq("table")
  end

  it "has the correct column headers" do
    html = render_weft_html { shipment_table shipments: [] }
    %w[Shipment Warehouse Items Driver Status].each do |header|
      expect(html).to include("<th>#{header}</th>")
    end
  end
end
