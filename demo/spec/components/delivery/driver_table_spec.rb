# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriverTable, type: :component do
  it "renders as a table" do
    component = render_arbre { driver_table drivers: [] }
    expect(component.tag_name).to eq("table")
  end

  it "has the correct column headers" do
    html = render_arbre_html { driver_table drivers: [] }
    %w[Driver Status Assignment Mileage].each do |header|
      expect(html).to include("<th>#{header}</th>")
    end
  end

  it "renders a Delivery::DriverRow for each driver" do
    drivers = 2.times.map { |i| Delivery::Driver.create!(name: "Driver #{i}") }
    html = render_arbre_html(drivers: drivers) { driver_table drivers: drivers }
    drivers.each do |driver|
      expect(html).to include(driver.name)
    end
  end
end
