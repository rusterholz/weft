# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::StatusBadge, type: :component do
  def badge(status) = described_class.render_element({}, nil, status: status)

  it "renders as a span" do
    expect(badge("shipped").tag_name).to eq("span")
  end

  it "includes badge CSS classes" do
    expect(badge("shipped").class_list).to include("badge", "badge-status", "badge-shipped")
  end

  it "converts underscored statuses to dashed CSS classes" do
    expect(badge("in_transit").class_list).to include("badge-in-transit")
  end

  it "displays status text with spaces instead of underscores" do
    expect(badge("in_transit").to_s).to include("in transit")
  end

  it "takes the status as a handoff, never as an HTML attribute" do
    expect(badge("shipped").to_s).not_to include('status="shipped"')
  end

  it "gives badges of one status their own slots, so a table can list many" do
    html = DropshipUI::Card.render({}, nil) do
      status_badge status: "shipped"
      status_badge status: "shipped"
    end

    ids = html.scan(/<span[^>]*id="([^"]+)"/).flatten
    expect(ids.size).to eq(2)
    expect(ids.uniq.size).to eq(2)
  end
end
