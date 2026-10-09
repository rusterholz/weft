# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::StatCard, type: :component do
  it "renders with stat-card class" do
    card = described_class.render_element({}, nil, label: "Submitted", value: 0)
    expect(card.class_list).to include("stat-card")
  end

  it "includes border-{accent} class when accent given" do
    card = described_class.render_element({}, nil, label: "Shipped", value: 0, accent: "shipped")
    expect(card.class_list).to include("border-shipped")
  end

  it "displays the label and value" do
    html = described_class.render({}, nil, label: "Late", value: 3)
    expect(html).to include("Late")
    expect(html).to include("3")
  end

  it "renders without an accent if none is given" do
    card = described_class.render_element({}, nil, label: "Plain", value: 1)
    expect(card.class_list.to_a.grep(/^border-/)).to be_empty
  end
end
