# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriversPage, type: :component do
  before do
    Delivery::Driver.create!(name: "Alice")
  end

  it "auto-routes at /drivers" do
    expect(described_class.page_path).to eq("/drivers")
    expect(described_class).to be_routable
  end

  def rendered = described_class.render

  it "renders the Drivers heading" do
    expect(rendered).to include("Drivers")
  end

  it "renders the drivers panel content" do
    expect(rendered).to include("Driver Roster")
    expect(rendered).to include("Alice")
  end
end
