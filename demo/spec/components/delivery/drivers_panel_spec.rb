# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriversPanel, type: :component do
  before do
    Delivery::Driver.create!(name: "Alice")
    Delivery::Driver.create!(name: "Bob")
  end

  it "renders a content card with the driver count" do
    html = render_weft_html { drivers_panel }
    expect(html).to include("Driver Roster (2)")
  end

  it "renders the driver table with all drivers" do
    html = render_weft_html { drivers_panel }
    expect(html).to include("Alice")
    expect(html).to include("Bob")
    expect(html.scan(%r{<tr[^>]*>.*?</tr>}m).size).to be >= 2
  end

  it "renders pagination for large result sets" do
    28.times { |i| Delivery::Driver.create!(name: "Driver#{i}") }
    html = render_weft_html { drivers_panel }
    expect(html).to include("Page 1 of 2")
    expect(html).to include("Next")
  end

  it "respects the page attribute" do
    28.times { |i| Delivery::Driver.create!(name: "Driver#{i}") }
    html = render_weft_html { drivers_panel(page: 2) }
    expect(html).to include("Page 2 of")
  end
end
