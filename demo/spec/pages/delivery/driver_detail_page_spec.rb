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
    render_weft_html(wire: { "driver_id" => driver.id }) { insert_tag(klass) }
  end

  it "renders the driver's three sections" do
    html = rendered
    expect(html).to include("Alice Cooper")
    # Each driver_*_section renders its own card; check for at least one section anchor.
    expect(html.scan(/<section|driver-.*?-section|content-card/).size).to be >= 3
  end

  # A well-formed uuid that addresses nothing. It has to be well-formed to
  # reach the lookup at all: `type: :uuid` refuses a value that is not a uuid
  # before any query happens, which is the separate claim below.
  it "raises ActiveRecord::RecordNotFound for a well-formed id matching no driver" do
    klass = described_class
    expect do
      render_weft_html(wire: { "driver_id" => "00000000-0000-4000-8000-000000000000" }) { insert_tag(klass) }
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  # The other half, and a different failure entirely: this one never reaches
  # the database. "not a uuid" and "a uuid nobody has" are distinct answers,
  # and conflating them sends an unreadable request to the lookup to find out.
  it "refuses an id that is not a uuid at all, before any lookup" do
    klass = described_class
    expect do
      render_weft_html(wire: { "driver_id" => "wombat" }) { insert_tag(klass) }
    end.to raise_error(Weft::InvalidParamValue, /wombat/)
  end
end
