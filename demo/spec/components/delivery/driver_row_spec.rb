# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriverRow, type: :component do
  let(:driver) { Delivery::Driver.create!(name: "Alice Martinez", total_mileage: 42.5) }

  it "renders as a tr" do
    component = render_arbre(driver: driver) { driver_row driver: driver }
    expect(component.tag_name).to eq("tr")
  end

  it "shows the driver name" do
    html = render_arbre_html(driver: driver) { driver_row driver: driver }
    expect(html).to include("Alice Martinez")
  end

  it "shows available badge when no assignment" do
    html = render_arbre_html(driver: driver) { driver_row driver: driver }
    expect(html).to include("badge-available")
  end

  it "shows busy badge when assigned" do
    driver.update!(current_shipment_id: "some-shipment-id")
    html = render_arbre_html(driver: driver) { driver_row driver: driver }
    expect(html).to include("badge-busy")
  end

  it "links to shipment when assigned" do
    driver.update!(current_shipment_id: "abcd1234-5678")
    html = render_arbre_html(driver: driver) { driver_row driver: driver }
    expect(html).to include('href="/shipments/abcd1234-5678"')
  end

  it "shows formatted mileage" do
    html = render_arbre_html(driver: driver) { driver_row driver: driver }
    expect(html).to include("42.5")
  end
end
