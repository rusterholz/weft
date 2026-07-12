# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::StatCard, type: :component do
  it "renders with stat-card class" do
    component = render_weft { stat_card label: "Submitted", value: 0 }
    expect(component.class_list).to include("stat-card")
  end

  it "includes border-{accent} class when accent given" do
    component = render_weft { stat_card label: "Shipped", value: 0, accent: "shipped" }
    expect(component.class_list).to include("border-shipped")
  end

  it "displays the label and value" do
    html = render_weft_html { stat_card label: "Submitted", value: 7 }
    expect(html).to include("Submitted")
    expect(html).to include("7")
  end

  it "renders without an accent if none is given" do
    component = render_weft { stat_card label: "Plain", value: 1 }
    expect(component.class_list.to_a.grep(/^border-/)).to be_empty
  end
end
