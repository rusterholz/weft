# frozen_string_literal: true

require "spec_helper"

# The drills page's companion-failure card, driven the way the button drives
# it. The host's action succeeds; the companion it brings along raises.
RSpec.describe "Companion failure drill", type: :request do
  subject(:response) do
    weft_post("/_components/drills/companion_host/break_companion", params: { "runs" => "2" })
  end

  before { allow(Weft.logger).to receive(:error) }

  it "succeeds, because the action did" do
    expect(response.status).to eq(200)
  end

  it "re-renders the host with its counter advanced" do
    expect(response.body).to include(%(id="drills-companion-host-3"))
    expect(response.body).to include("has run 3 time(s)")
  end

  it "reports the failure in the companion's own slot, the one already on the page" do
    expect(response.body).to include(%(id="drills-flaky-companion-drill"))
    expect(response.body).to match(/id="drills-flaky-companion-drill"[^>]*hx-swap-oob="true"/)
  end

  it "shows the branded error there rather than the companion's usual body" do
    expect(response.body).to include("Something went wrong")
    expect(response.body).not_to include("Riding along quietly")
  end
end
