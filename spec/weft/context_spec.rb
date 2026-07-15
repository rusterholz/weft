# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Context do
  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "OrderHeader"
      param :order_id
      performs(:advance) { nil }

      def build(attributes = {})
        super
        yield if block_given?
      end
    end
  end

  describe "action: kwarg expansion" do
    it "expands action: into htmx attributes on a button" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 42) do
          button "Advance", action: :advance
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include('hx-target="#order-header-42"')
      expect(html).to include('hx-swap="outerHTML"')
      expect(html).to include("hx-vals")
    end

    it "expands action: on any element, not just buttons" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          span "click me", action: :advance
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include("<span")
    end

    it "works inside nested element blocks" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 7) do
          div class: "wrapper" do
            div class: "inner" do
              button "Deep", action: :advance
            end
          end
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include('hx-target="#order-header-7"')
    end

    it "preserves other attributes alongside htmx attrs" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", action: :advance, class: "btn btn-primary", disabled: "disabled"
        end
      end.to_s

      expect(html).to include('class="btn btn-primary"')
      expect(html).to include('disabled="disabled"')
      expect(html).to include("hx-post=")
    end

    it "does not interfere with elements that have no action:" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          span "plain"
          button "Advance", action: :advance
        end
      end.to_s

      # The span should have no htmx attrs
      expect(html).to include("<span>plain</span>")
    end

    it "preserves HTML action attribute (string value) on forms" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          form(method: "post", action: "/orders") do
            input type: "submit", value: "Create"
          end
        end
      end.to_s

      expect(html).to include('action="/orders"')
      expect(html).not_to include("hx-post")
    end

    describe "on form elements" do
      it "expands action: into both htmx attrs and the HTML action and method attributes" do
        klass = component_class
        html = described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            form(action: :advance) do
              input type: "submit", value: "Submit"
            end
          end
        end.to_s

        expect(html).to include('hx-post="/_components/order_header/advance"')
        expect(html).to include('action="/_components/order_header/advance"')
        expect(html).to include('method="post"')
      end

      it "omits hx-vals on forms so form fields are the sole payload" do
        klass = component_class
        html = described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            form(action: :advance) do
              input type: "submit", value: "Submit"
            end
          end
        end.to_s

        expect(html).not_to include("hx-vals")
      end

      it "still emits hx-vals on non-form elements" do
        klass = component_class
        html = described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            button "Advance", action: :advance
          end
        end.to_s

        expect(html).to include("hx-vals")
      end
    end
  end

  describe "trigger: kwarg" do
    it "sets hx-trigger alongside action: expansion" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          select action: :advance, trigger: "change"
        end
      end.to_s

      expect(html).to include('hx-trigger="change"')
      expect(html).to include("hx-post=")
    end

    it "sets hx-trigger alone without action:" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div trigger: "every 10s"
        end
      end.to_s

      expect(html).to include('hx-trigger="every 10s"')
      expect(html).not_to include("hx-post")
    end
  end

  describe "navigate: kwarg expansion" do
    it "expands navigate: into htmx GET attrs targeting the nearest component" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 42) do
          button "Next", navigate: { order_id: 43 }
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header?order_id=43"')
      expect(html).to include('hx-target="#order-header-42"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "preserves other attributes alongside navigate attrs" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", navigate: { order_id: 2 }, class: "btn", "hx-push-url" => "/orders/2"
        end
      end.to_s

      expect(html).to include('class="btn"')
      expect(html).to include('hx-push-url="/orders/2"')
      expect(html).to include("hx-get=")
    end

    it "works with trigger: alongside navigate:" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div navigate: { order_id: 2 }, trigger: "revealed"
        end
      end.to_s

      expect(html).to include('hx-trigger="revealed"')
      expect(html).to include("hx-get=")
    end

    it "does not interfere with action:" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Advance", action: :advance
          button "Next", navigate: { order_id: 2 }
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include('hx-get="/_components/order_header?order_id=2"')
    end
  end

  describe "find_action_context (innermost component wins)" do
    it "finds the action on the innermost enclosing component" do # rubocop:disable RSpec/ExampleLength
      inner_class = Class.new(Weft::Component) do
        def self.name = "InnerCard"
        param :item_id
        performs(:wombat) { nil }

        def build(attributes = {})
          super
          yield if block_given?
        end
      end

      outer = component_class
      inner = inner_class
      html = described_class.new({}, nil) do
        insert_tag(outer, order_id: 1) do
          insert_tag(inner, item_id: 5) do
            button "Wombat", action: :wombat
          end
        end
      end.to_s

      # Should target InnerCard, not OrderHeader
      expect(html).to include('hx-post="/_components/inner_card/wombat"')
      expect(html).to include('hx-target="#inner-card-5"')
    end

    it "walks up to a parent component if the inner one lacks the action" do # rubocop:disable RSpec/ExampleLength
      inner_class = Class.new(Weft::Component) do
        def self.name = "PlainInner"
        param :item_id

        def build(attributes = {})
          super
          yield if block_given?
        end
      end

      outer = component_class
      inner = inner_class
      html = described_class.new({}, nil) do
        insert_tag(outer, order_id: 3) do
          insert_tag(inner, item_id: 9) do
            button "Advance", action: :advance
          end
        end
      end.to_s

      # PlainInner doesn't define :advance, so it falls through to OrderHeader
      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include('hx-target="#order-header-3"')
    end
  end

  describe "loads: kwarg expansion" do
    let(:target_class) do
      Class.new(Weft::Component) do
        def self.name = "ShipmentSummary"
        param :shipment_id

        def build(attributes = {})
          super
          span "summary-#{params.shipment_id}"
        end
      end
    end

    it "generates hx-get with component path and with: attrs" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { shipment_id: "42" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/shipment_summary?shipment_id=42"')
    end

    it "generates hx-swap from swap symbol" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).to include('hx-swap="innerHTML"')
    end

    it "generates hx-target from CSS selector string" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tooltip-zone"
        end
      end.to_s

      expect(html).to include('hx-target="#tooltip-zone"')
    end

    it "generates hx-target from :self symbol" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div loads: target, with: { shipment_id: "1" },
              swap: :fill, target: :self
        end
      end.to_s

      expect(html).to include('hx-target="this"')
    end

    it "generates hx-target from Arbre element reference" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          tip = div(id: "tip-99", class: "tooltip-zone")
          button "Hover", loads: target, with: { shipment_id: "99" },
                          swap: :fill, target: tip
        end
      end.to_s

      expect(html).to include('hx-target="#tip-99"')
    end

    it "generates hx-trigger when trigger: is provided" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div loads: target, with: { shipment_id: "1" },
              swap: :fill, target: :self, trigger: :hover
        end
      end.to_s

      expect(html).to include('hx-trigger="mouseenter once"')
    end

    it "omits hx-trigger when trigger: is not provided" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).not_to include("hx-trigger")
    end

    it "defaults with: to nearest component attrs when omitted" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 77) do
          div loads: target, swap: :fill, target: :self
        end
      end.to_s

      expect(html).to include('hx-get="/_components/shipment_summary?order_id=77"')
    end

    it "preserves other attributes alongside loads: attrs" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tip", class: "btn"
        end
      end.to_s

      expect(html).to include('class="btn"')
      expect(html).to include("hx-get=")
    end

    it "raises when swap: is missing" do
      target = target_class
      klass = component_class
      expect do
        described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            button "Load", loads: target, target: "#tip"
          end
        end.to_s
      end.to raise_error(ArgumentError, /swap/)
    end

    it "raises when target: is missing" do
      target = target_class
      klass = component_class
      expect do
        described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            button "Load", loads: target, swap: :fill
          end
        end.to_s
      end.to raise_error(ArgumentError, /target/)
    end
  end

  describe "push_url: kwarg" do
    it "generates hx-push-url with string value" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Filter", action: :advance, push_url: "/orders?status=shipped"
        end
      end.to_s

      expect(html).to include('hx-push-url="/orders?status=shipped"')
      expect(html).to include("hx-post=")
    end

    it "generates hx-push-url with true" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", action: :advance, push_url: true
        end
      end.to_s

      expect(html).to include('hx-push-url="true"')
    end

    it "works alongside loads:" do
      target = Class.new(Weft::Component) do
        def self.name = "PushTarget"
        param :id
      end
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Load", loads: target, with: { id: "1" },
                         swap: :fill, target: "#panel",
                         push_url: "/items/1"
        end
      end.to_s

      expect(html).to include('hx-push-url="/items/1"')
      expect(html).to include("hx-get=")
    end
  end

  describe "preset kwarg dispatch" do
    let(:target_class) do
      Class.new(Weft::Component) do
        def self.name = "PresetTarget"
        param :item_id

        def build(attributes = {})
          super
          span "item-#{params.item_id}"
        end
      end
    end

    before do
      Weft.register_preset :test_short, trigger: :hover, swap: :fill
    end

    after do
      Weft::Presets.send(:registry).delete(:test_short)
    end

    it "dispatches a registered preset kwarg through loads: expansion" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Hover me", test_short: target,
                             with: { item_id: "5" }, target: "#tip"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/preset_target?item_id=5"')
      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('hx-target="#tip"')
    end

    it "applies preset trigger as hx-trigger" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div test_short: target, with: { item_id: "1" }, target: :self
        end
      end.to_s

      expect(html).to include('hx-trigger="mouseenter once"')
    end

    it "allows user trigger: to override preset trigger" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div test_short: target, with: { item_id: "1" }, target: :self,
              trigger: :click
        end
      end.to_s

      expect(html).to include('hx-trigger="click"')
      expect(html).not_to include("mouseenter")
    end

    it "uses preset target when provided by the preset" do
      Weft.register_preset :self_target, trigger: :visible, swap: :fill, target: :self
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div self_target: target, with: { item_id: "1" }
        end
      end.to_s

      expect(html).to include('hx-target="this"')
      Weft::Presets.send(:registry).delete(:self_target)
    end

    it "requires target when preset has no default target" do
      target = target_class
      klass = component_class
      expect do
        described_class.new({}, nil) do
          insert_tag(klass, order_id: 1) do
            button "Nope", test_short: target, with: { item_id: "1" }
          end
        end.to_s
      end.to raise_error(ArgumentError, /target/)
    end

    it "passes through unregistered kwargs without expansion" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Normal", data_foo: "bar"
        end
      end.to_s

      expect(html).not_to include("hx-get")
    end

    it "preserves other attributes alongside preset attrs" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Hover", test_short: target, with: { item_id: "1" },
                          target: "#tip", class: "btn"
        end
      end.to_s

      expect(html).to include('class="btn"')
      expect(html).to include("hx-get=")
    end

    it "defaults with: to nearest component attrs when omitted" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 42) do
          div test_short: target, target: :self
        end
      end.to_s

      expect(html).to include('hx-get="/_components/preset_target?order_id=42"')
    end
  end

  # Retry-style presets carry a URL string (not a target Class): the caller
  # already has the exact URL to re-fetch, so there's nothing to derive. The URL
  # becomes hx-get directly; swap/target/trigger still come from the preset.
  describe "URL-valued preset dispatch" do
    before { Weft.register_preset :test_url, trigger: :click, swap: :fill, target: "#box" }
    after  { Weft::Presets.send(:registry).delete(:test_url) }

    it "expands a String-valued preset kwarg into a direct hx-get to that URL" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", test_url: "/_components/thing?id=9"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/thing?id=9"')
      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('hx-target="#box"')
      expect(html).to include('hx-trigger="click"')
    end

    it "honors per-call target: and swap: overrides over the preset" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", test_url: "/x", target: "#other", swap: :outer_html
        end
      end.to_s

      expect(html).to include('hx-target="#other"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "does not treat a String value for an unregistered kwarg name as a preset" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Go", data_url: "/x"
        end
      end.to_s

      expect(html).not_to include("hx-get")
    end
  end

  describe "shipped preset presets" do
    let(:target_class) do
      Class.new(Weft::Component) do
        def self.name = "PresetTarget"
        param :id
      end
    end

    def render_with_preset(preset_name, **kwargs)
      target = target_class
      klass = component_class
      name = preset_name
      described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          div({ name => target, with: { id: "1" } }.merge(kwargs))
        end
      end.to_s
    end

    it "tooltip: hover + fill" do
      html = render_with_preset(:tooltip, target: "#tip")

      expect(html).to include('hx-trigger="mouseenter once"')
      expect(html).to include('hx-swap="innerHTML"')
    end

    it "inline_expand: click + after" do
      html = render_with_preset(:inline_expand, target: "closest tr")

      expect(html).to include('hx-swap="afterend"')
      expect(html).to include('hx-trigger="click"')
    end

    it "lazy: visible + fill + self" do
      html = render_with_preset(:lazy)

      expect(html).to include('hx-trigger="revealed"')
      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('hx-target="this"')
    end

    it "modal: click + fill" do
      html = render_with_preset(:modal, target: "#modal-body")

      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('hx-trigger="click"')
    end

    it "load_more: click + replace + self" do
      html = render_with_preset(:load_more)

      expect(html).to include('hx-swap="outerHTML"')
      expect(html).to include('hx-target="this"')
      expect(html).to include('hx-trigger="click"')
    end

    it "infinite_scroll: visible + after" do
      html = render_with_preset(:infinite_scroll, target: :self)

      expect(html).to include('hx-trigger="revealed"')
      expect(html).to include('hx-swap="afterend"')
    end

    it "live_search: debounced input + fill" do
      html = render_with_preset(:live_search, target: "#results")

      expect(html).to include('hx-trigger="input changed delay:300ms"')
      expect(html).to include('hx-swap="innerHTML"')
    end

    it "tabs: click + fill" do
      html = render_with_preset(:tabs, target: "#panel")

      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('hx-trigger="click"')
    end

    it "retry: click + outerHTML + closest .weft-error, hx-get to the given URL" do
      klass = component_class
      html = described_class.new({}, nil) do
        insert_tag(klass, order_id: 1) do
          button "Retry", retry: "/_components/order_header?order_id=1"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header?order_id=1"')
      expect(html).to include('hx-swap="outerHTML"')
      expect(html).to include('hx-target="closest .weft-error"')
      expect(html).to include('hx-trigger="click"')
    end
  end

  describe "Component.render uses Weft::Context" do
    it "supports action: kwargs in render output" do
      klass = Class.new(Weft::Component) do
        def self.name = "RenderTest"
        param :order_id
        performs(:go) { nil }

        def build(attributes = {})
          super
          button "Go", action: :go
        end
      end

      html = klass.render(order_id: 1)

      expect(html).to include('hx-post="/_components/render_test/go"')
    end
  end
end
