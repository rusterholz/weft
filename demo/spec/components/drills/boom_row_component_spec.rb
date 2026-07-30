# frozen_string_literal: true

require "spec_helper"

RSpec.describe Drills::BoomRowComponent, type: :component do
  it "is routable so its delete action has a live route" do
    expect(described_class.resolved_component_path).to eq("/_components/drills/boom_row")
    expect(described_class).to be_routable
  end

  it "declares a delete-swap removal whose callable always fails" do
    action = described_class.actions[%i[remove delete]]

    expect(action.swap).to eq(:delete)
    expect { Weft::DSL::Sandbox.run(Weft::Params.new({}), &action.callable) }.
      to raise_error(RuntimeError, /drill/)
  end

  it "renders as a table row with a confirmed delete trigger" do
    html = render_weft_html { boom_row label: "Doomed row" }

    expect(html).to match(/\A<tr\b/)
    expect(html).to include("Doomed row")
    expect(html).to include('hx-delete="/_components/drills/boom_row/remove"')
    expect(html).to include("hx-confirm=")
  end
end
