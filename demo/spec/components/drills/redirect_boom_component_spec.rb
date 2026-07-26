# frozen_string_literal: true

require "spec_helper"

RSpec.describe Drills::RedirectBoomComponent, type: :component do
  it "raises its own Failure on every build" do
    expect { described_class.render }.to raise_error(described_class::Failure)
  end

  it "recovers from Failure by transferring to the dashboard page" do
    entry = described_class.recovery_for(described_class::Failure.new)
    expect(entry[:with]).to eq(DashboardPage)
  end
end
