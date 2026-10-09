# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriverRow, type: :component do
  let(:driver) { Delivery::Driver.create!(name: "Alice Martinez", total_mileage: 42.5) }

  def render_row = described_class.render({}, nil, driver: driver)

  it "renders as a tr" do
    expect(described_class.render_element({}, nil, driver: driver).tag_name).to eq("tr")
  end

  it "shows the driver name" do
    html = render_row
    expect(html).to include("Alice Martinez")
  end

  it "shows available badge when no assignment" do
    html = render_row
    expect(html).to include("badge-available")
  end

  it "shows busy badge when assigned" do
    driver.update!(current_shipment_id: "some-shipment-id")
    html = render_row
    expect(html).to include("badge-busy")
  end

  it "links to shipment when assigned" do
    driver.update!(current_shipment_id: "abcd1234-5678")
    html = render_row
    expect(html).to include('href="/shipments/abcd1234-5678"')
  end

  it "shows formatted mileage" do
    html = render_row
    expect(html).to include("42.5")
  end
end
