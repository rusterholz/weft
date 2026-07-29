# frozen_string_literal: true

require "spec_helper"

RSpec.describe Logistics::OutageSwitch, type: :component do
  after { Logistics::ShipmentFeedOutage.toggle! if Logistics::ShipmentFeedOutage.active? }

  def render_switch
    render_weft_html { insert_tag(Logistics::OutageSwitch) }
  end

  it "offers to simulate an outage while the feed is healthy" do
    html = render_switch

    expect(html).to include("Simulate shipments outage")
    expect(html).to include('hx-post="/_components/logistics/outage_switch/toggle"')
  end

  it "asks for confirmation before breaking the feed, but not before restoring it" do
    expect(render_switch).to include('hx-confirm="Break the live shipments feed for every viewer?"')

    Logistics::ShipmentFeedOutage.toggle!
    expect(render_switch).not_to include("hx-confirm")
  end

  it "shows the active badge and end control during an outage" do
    Logistics::ShipmentFeedOutage.toggle!

    html = render_switch

    expect(html).to include("Outage active")
    expect(html).to include("End outage")
    expect(html).not_to include("Simulate shipments outage")
  end
end
