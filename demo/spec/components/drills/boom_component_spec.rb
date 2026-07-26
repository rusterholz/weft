# frozen_string_literal: true

require "spec_helper"

RSpec.describe Drills::BoomComponent, type: :component do
  it "is routable at its derived path so the drill trigger can fetch it" do
    expect(described_class.resolved_component_path).to eq("/_components/drills/boom")
    expect(described_class).to be_routable
  end

  it "raises on every build" do
    expect { described_class.render }.to raise_error(RuntimeError, /drill/)
  end
end
