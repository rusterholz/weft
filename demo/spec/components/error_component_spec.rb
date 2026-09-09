# frozen_string_literal: true

require "spec_helper"

# The app-level error component (wired via Weft.configuration.error_component)
# models the user-extension pattern: it restyles the error box as a DropshipUI
# content-card but renders the retry control through the gem's :retry preset,
# so it never hand-writes htmx.
RSpec.describe ErrorComponent, type: :component do
  def render_error(**attrs)
    render_weft_html(wire: attrs) { insert_tag(ErrorComponent) }
  end

  it "renders the retry button via the :retry preset" do
    html = render_error(retry_url: "/_components/oms/order_row?order_id=5", status_code: 500)

    expect(html).to include("Retry")
    expect(html).to include('hx-get="/_components/oms/order_row?order_id=5"')
    expect(html).to include('hx-target="closest .weft-error"')
    expect(html).to include('hx-swap="outerHTML"')
    expect(html).to include('hx-trigger="click"')
  end

  it "keeps the inherited .weft-error class so retry's outerHTML swap targets the box" do
    html = render_error(retry_url: "/x", status_code: 500)

    expect(html).to include("weft-error")
    expect(html).to include("content-card")
  end

  it "omits the retry button when no retry_url is present" do
    html = render_error(status_code: 500)

    expect(html).not_to include("Retry")
  end

  # The push error card names the component that went quiet, so a page
  # streaming several of them says which one stopped. That title is a
  # derivation of the failing card — and on the outage drill it is derived from
  # the very query that broke, so reading it bare would re-raise.
  describe "naming the card that went quiet" do
    let(:order) { Oms::Order.create!(customer_name: "Acme", lat: 0.0, lon: 0.0, status: "processing") }

    def render_push_error_for(card_class, order_id)
      state = Weft::Params::Assembly.for_request(card_class, { "order_id" => order_id })
      Weft::Context.new({}, nil,
                        wire_params: { attempts_remaining: 2, status_code: 500 },
                        branch_bag: state) { insert_tag(ErrorComponent) }.to_s
    end

    it "uses the failed card's own title when the derivation still answers" do
      html = render_push_error_for(Logistics::ShipmentsCard, order.id)

      expect(html).to include("Shipments (0)")
      expect(html).to match(/interrupted/i)
    end

    it "falls back to the plain wording when that title is what failed" do
      Logistics::ShipmentFeedOutage.toggle! unless Logistics::ShipmentFeedOutage.active?

      html = render_push_error_for(Logistics::ShipmentsCard, order.id)

      expect(html).to match(/live updates interrupted/i)
      expect(html).not_to include("Shipments (")
    ensure
      Logistics::ShipmentFeedOutage.toggle! if Logistics::ShipmentFeedOutage.active?
    end
  end

  it "renders the retrying live-updates state while push attempts remain" do
    html = render_error(exception: RuntimeError.new("feed down"),
                        attempts_remaining: 2, retry_url: "/x", status_code: 500)

    expect(html).to match(/live updates interrupted/i)
    expect(html).to include("Retrying")
    expect(html).not_to include("Resume live updates")
  end

  it "renders the stopped state with a resume button via the :reopen_stream preset" do
    html = render_error(attempts_remaining: 0,
                        retry_url: "/_components/logistics/shipments_card?order_id=5",
                        status_code: 500)

    expect(html).to match(/live updates stopped/i)
    expect(html).to include("Resume live updates")
    expect(html).to include('hx-get="/_components/logistics/shipments_card?order_id=5"')
    expect(html).to include('hx-target="closest [sse-swap]"')
    expect(html).to include('hx-swap="outerHTML"')
  end
end
