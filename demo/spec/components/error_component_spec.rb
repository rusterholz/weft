# frozen_string_literal: true

require "spec_helper"

# The app-level error component (wired via Weft.configuration.error_component)
# models the user-extension pattern: it restyles the error box as a DropshipUI
# content-card but renders the retry control through the gem's :retry shorthand,
# so it never hand-writes htmx.
RSpec.describe ErrorComponent, type: :component do
  def render_error(**attrs)
    render_weft_html { insert_tag(ErrorComponent, **attrs) }
  end

  it "renders the retry button via the :retry shorthand" do
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
end
