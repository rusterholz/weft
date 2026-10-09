# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::ShipmentTable, type: :component do
  it "renders as a table" do
    expect(described_class.render_element({}, nil, shipments: []).tag_name).to eq("table")
  end

  it "has the correct column headers" do
    html = described_class.render({}, nil, shipments: [])
    %w[Shipment Warehouse Items Driver Status].each do |header|
      expect(html).to include("<th>#{header}</th>")
    end
  end
end
