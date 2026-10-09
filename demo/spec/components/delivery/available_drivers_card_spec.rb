# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::AvailableDriversCard, type: :component do
  it "displays the available/total driver count" do
    Delivery::Driver.create!(name: "Alice")
    Delivery::Driver.create!(name: "Bob")
    html = described_class.render({}, nil)

    expect(html).to include("Drivers")
    expect(html).to include("2/2")
  end

  it "renders a stat-card with the 'available' accent" do
    card = described_class.render_element({}, nil)
    expect(card.class_list).to include("stat-card", "border-available")
  end

  it "includes auto-generated refresh attributes" do
    html = described_class.render({}, nil)
    expect(html).to include('hx-trigger="every 10s"')
    expect(html).to include('hx-get="/_components/delivery/available_drivers_card"')
    expect(html).to include('hx-swap="outerHTML"')
  end
end
