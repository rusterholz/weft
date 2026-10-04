# frozen_string_literal: true

require "spec_helper"

RSpec.describe Drills::BoomPage, type: :component do
  it "routes at /drills/boom" do
    expect(described_class.page_path).to eq("/drills/boom")
    expect(described_class).to be_routable
  end

  it "raises on every build" do
    expect { described_class.render }.to raise_error(RuntimeError, /drill/)
  end
end
