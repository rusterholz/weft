# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::StatusBadge, type: :component do
  it "renders as a span" do
    component = render_arbre { status_badge "shipped" }
    expect(component.tag_name).to eq("span")
  end

  it "includes badge CSS classes" do
    component = render_arbre { status_badge "shipped" }
    expect(component.class_list).to include("badge", "badge-status", "badge-shipped")
  end

  it "converts underscored statuses to dashed CSS classes" do
    component = render_arbre { status_badge "in_transit" }
    expect(component.class_list).to include("badge-in-transit")
  end

  it "displays status text with spaces instead of underscores" do
    html = render_arbre_html { status_badge "in_transit" }
    expect(html).to include("in transit")
  end
end
