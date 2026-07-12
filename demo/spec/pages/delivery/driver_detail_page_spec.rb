# frozen_string_literal: true

require "spec_helper"

RSpec.describe Delivery::DriverDetailPage, type: :component do
  let(:driver) { Delivery::Driver.create!(name: "Alice Cooper") }

  it "auto-routes at /drivers/:driver_id" do
    expect(described_class.page_path).to eq("/drivers/:driver_id")
    expect(described_class).to be_routable
  end

  def rendered
    klass = described_class
    id = driver.id
    render_weft_html { insert_tag(klass, driver_id: id) }
  end

  it "renders the driver's three sections" do
    html = rendered
    expect(html).to include("Alice Cooper")
    # Each driver_*_section renders its own card; check for at least one section anchor.
    expect(html.scan(/<section|driver-.*?-section|content-card/).size).to be >= 3
  end
end
