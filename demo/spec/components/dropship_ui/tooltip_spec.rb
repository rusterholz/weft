# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::Tooltip, type: :component do
  let(:content_class) do
    Class.new(Weft::Component) do
      def self.name = "TooltipContentStub"
      param :id
    end
  end

  it "wraps the trigger content and renders a popover scaffold" do
    klass = content_class
    html = render_weft_html { tooltip(content: klass, with: { id: 1 }) { text_node "3 items" } }
    expect(html).to include("weft-tooltip-wrap")
    expect(html).to include("weft-tooltip-trigger")
    expect(html).to include("3 items")
    expect(html).to include("weft-tooltip")
  end

  it "wires the popover with htmx attrs via the tooltip: shorthand" do
    klass = content_class
    html = render_weft_html { tooltip(content: klass, with: { id: 1 }) { text_node "hover" } }
    expect(html).to include('hx-get="/_components/tooltip_content_stub?id=1"')
    expect(html).to include('hx-trigger="mouseenter once from:closest .weft-tooltip-wrap"')
    expect(html).to include('hx-swap="innerHTML"')
  end

  it "renders a placeholder loading state until hovered" do
    klass = content_class
    html = render_weft_html { tooltip(content: klass, with: { id: 1 }) { text_node "hover me" } }
    expect(html).to include("Loading")
  end

  it "places trigger content before the popover" do
    klass = content_class
    html = render_weft_html { tooltip(content: klass, with: { id: 1 }) { text_node "trigger-content" } }
    trigger_idx = html.index("trigger-content")
    popover_idx = html.index('class="weft-tooltip"')
    expect(trigger_idx).to be < popover_idx
  end
end
