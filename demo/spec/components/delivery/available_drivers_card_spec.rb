# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::AvailableDriversCard, type: :component do
  it "displays the available/total driver count" do
    Delivery::Driver.create!(name: "Alice")
    Delivery::Driver.create!(name: "Bob")
    html = render_weft_html { available_drivers_card }

    expect(html).to include("Drivers")
    expect(html).to include("2/2")
  end

  it "renders a stat-card with the 'available' accent" do
    component = render_weft { available_drivers_card }
    expect(component.to_s).to include("border-available")
  end

  it "includes auto-generated refresh attributes" do
    html = render_weft_html { available_drivers_card }
    expect(html).to include('hx-trigger="every 10s"')
    expect(html).to include('hx-get="/_components/delivery/available_drivers_card"')
    expect(html).to include('hx-swap="outerHTML"')
  end
end
