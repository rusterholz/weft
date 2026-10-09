# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriverTable, type: :component do
  it "renders as a table" do
    expect(described_class.render_element({}, nil, drivers: []).tag_name).to eq("table")
  end

  it "has the correct column headers" do
    html = described_class.render({}, nil, drivers: [])
    %w[Driver Status Assignment Mileage].each do |header|
      expect(html).to include("<th>#{header}</th>")
    end
  end

  it "renders a Delivery::DriverRow for each driver" do
    drivers = 2.times.map { |i| Delivery::Driver.create!(name: "Driver #{i}") }
    html = described_class.render({}, nil, drivers: drivers)
    drivers.each do |driver|
      expect(html).to include(driver.name)
    end
  end

  # The driver rides in as a handoff, which cannot compose a DOM id, so the
  # row derives the scalar that names it. Without that, every row on the page
  # wears the same id and only the first is addressable.
  it "gives each row its own element id, drawn from the driver it was handed" do
    drivers = 2.times.map { |i| Delivery::Driver.create!(name: "Driver #{i}") }
    html = described_class.render({}, nil, drivers: drivers)

    # The id carries the driver's UUID whole, dashes included. A uuid is the one
    # value A′ composition does not sanitize dash-free, because its width is
    # fixed and so its boundaries are unambiguous without the separator marking
    # them — and the row says which it is by declaring `type: :uuid` on the
    # derivation, exactly as it would on a param.
    drivers.each do |driver|
      expect(html).to include(%(id="delivery-driver-row-#{driver.id}"))
    end
  end
end
