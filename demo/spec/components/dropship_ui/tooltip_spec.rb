# frozen_string_literal: true

require "spec_helper"

# One constant, defined once: every Weft::Component subclass self-registers,
# so building the stub per-example would register several distinct class
# objects at the same route and trip collision detection on the first request.
TooltipContentStub = Class.new(Weft::Component) { param :id }

RSpec.describe DropshipUI::Tooltip, type: :component do
  def render_tooltip(trigger)
    described_class.render({}, nil, content: TooltipContentStub, with: { id: 1 }) { text_node trigger }
  end

  it "wraps the trigger content and renders a popover scaffold" do
    html = render_tooltip("3 items")
    expect(html).to include("weft-tooltip-wrap")
    expect(html).to include("weft-tooltip-trigger")
    expect(html).to include("3 items")
    expect(html).to include("weft-tooltip")
  end

  it "wires the popover with htmx attrs via the tooltip: preset" do
    html = render_tooltip("hover")
    expect(html).to include('hx-get="/_components/tooltip_content_stub?id=1"')
    expect(html).to include('hx-trigger="mouseenter once from:closest .weft-tooltip-wrap"')
    expect(html).to include('hx-swap="innerHTML"')
  end

  it "renders a placeholder loading state until hovered" do
    expect(render_tooltip("hover me")).to include("Loading")
  end

  it "places trigger content before the popover" do
    html = render_tooltip("trigger-content")
    trigger_idx = html.index("trigger-content")
    popover_idx = html.index('class="weft-tooltip"')
    expect(trigger_idx).to be < popover_idx
  end
end
