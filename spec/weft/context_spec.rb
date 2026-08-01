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

  describe "wire params" do
    it "carries a wire params source provided at construction" do
      ctx = described_class.new({}, nil, wire_params: { "status" => "x" })

      expect(ctx.wire_params).to eq({ "status" => "x" })
    end

    it "defaults to an empty hash" do
      expect(described_class.new.wire_params).to eq({})
    end
  end

  describe "overlays" do
    it "carries request-scoped overlay values provided at construction" do
      ctx = described_class.new({}, nil, overlays: { page: 1 })

      expect(ctx.overlays).to eq({ page: 1 })
    end

    it "defaults to an empty hash" do
      expect(described_class.new.overlays).to eq({})
    end
  end

  describe "branch bag" do
    it "carries a bag for root components to branch from" do
      bag = Weft::Params.new({ order_id: 7 })
      ctx = described_class.new({}, nil, branch_bag: bag)

      expect(ctx.branch_bag).to be(bag)
    end

    it "defaults to nil" do
      expect(described_class.new.branch_bag).to be_nil
    end

    it "is readable inside the construction block" do
      seen = nil
      described_class.new({}, nil, wire_params: { "status" => "x" }) do
        seen = arbre_context.wire_params
      end

      expect(seen).to eq({ "status" => "x" })
    end
  end

  describe "action: kwarg expansion" do
    it "expands action: into htmx attributes on a button" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 42 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          span "click me", action: :advance
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include("<span")
    end

    it "works inside nested element blocks" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 7 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Go", action: :advance, class: "btn btn-primary", disabled: "disabled"
        end
      end.to_s

      expect(html).to include('class="btn btn-primary"')
      expect(html).to include('disabled="disabled"')
      expect(html).to include("hx-post=")
    end

    it "does not interfere with elements that have no action:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          span "plain"
          button "Advance", action: :advance
        end
      end.to_s

      # The span should have no htmx attrs
      expect(html).to include("<span>plain</span>")
    end

    it "preserves HTML action attribute (string value) on forms" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
        html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
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
        html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            form(action: :advance) do
              input type: "submit", value: "Submit"
            end
          end
        end.to_s

        expect(html).not_to include("hx-vals")
      end

      it "still emits hx-vals on non-form elements" do
        klass = component_class
        html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          select action: :advance, trigger: "change"
        end
      end.to_s

      expect(html).to include('hx-trigger="change"')
      expect(html).to include("hx-post=")
    end

    it "sets hx-trigger alone without action:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 42 }) do
        insert_tag(klass) do
          button "Next", navigate: { order_id: 43 }
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header?order_id=43"')
      expect(html).to include('hx-target="#order-header-42"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "preserves other attributes alongside navigate attrs" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Go", navigate: { order_id: 2 }, class: "btn", "hx-push-url" => "/orders/2"
        end
      end.to_s

      expect(html).to include('class="btn"')
      expect(html).to include('hx-push-url="/orders/2"')
      expect(html).to include("hx-get=")
    end

    it "works with trigger: alongside navigate:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div navigate: { order_id: 2 }, trigger: "revealed"
        end
      end.to_s

      expect(html).to include('hx-trigger="revealed"')
      expect(html).to include("hx-get=")
    end

    it "does not interfere with action:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Advance", action: :advance
          button "Next", navigate: { order_id: 2 }
        end
      end.to_s

      expect(html).to include('hx-post="/_components/order_header/advance"')
      expect(html).to include('hx-get="/_components/order_header?order_id=2"')
    end
  end

  describe "target:/swap: call-site overrides on action:" do
    it "overrides the action's hx-target with a call-site target:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 42 }) do
        insert_tag(klass) do
          button "Advance", action: :advance, target: "#detail-pane"
        end
      end.to_s

      expect(html).to include('hx-target="#detail-pane"')
      expect(html).not_to include('hx-target="#order-header-42"')
    end

    it "overrides the action's hx-swap with a call-site swap:" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Advance", action: :advance, swap: :fill
        end
      end.to_s

      expect(html).to include('hx-swap="innerHTML"')
    end

    it "resolves a :self target override to this" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Advance", action: :advance, target: :self
        end
      end.to_s

      expect(html).to include('hx-target="this"')
    end

    it "does not leak target: or swap: as literal HTML attributes" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Advance", action: :advance, target: "#pane", swap: :fill
        end
      end.to_s

      expect(html).not_to include(' target="#pane"')
      expect(html).not_to include(' swap="fill"')
    end

    it "applies overrides on form elements after the form augmentation" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          form(action: :advance, target: "#result", swap: :fill) do
            input type: "submit", value: "Submit"
          end
        end
      end.to_s

      expect(html).to include('hx-target="#result"')
      expect(html).to include('hx-swap="innerHTML"')
      expect(html).to include('action="/_components/order_header/advance"')
      expect(html).not_to include(' target="#result"')
    end
  end

  describe "target:/swap: call-site overrides on navigate:" do
    it "overrides the generated hx-target and hx-swap" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Next", navigate: { order_id: 2 }, target: "#list", swap: :append
        end
      end.to_s

      expect(html).to include('hx-target="#list"')
      expect(html).to include('hx-swap="beforeend"')
      expect(html).not_to include(' target="#list"')
      expect(html).not_to include(' swap="beforeend"')
    end
  end

  describe "confirm: kwarg" do
    it "maps to hx-confirm alongside action: without leaking chrome" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Delete", action: :advance, confirm: "Are you sure?"
        end
      end.to_s

      expect(html).to include('hx-confirm="Are you sure?"')
      expect(html).not_to include(" confirm=")
      expect(html).to include("hx-post=")
    end

    it "maps to hx-confirm standalone, for container-level inheritance" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div confirm: "Really?" do
            button "Advance", action: :advance
          end
        end
      end.to_s

      expect(html).to include('<div hx-confirm="Really?"')
    end

    it "maps to hx-confirm alongside a preset" do
      target = Class.new(Weft::Component) do
        def self.name = "ConfirmTarget"
        param :id
      end
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Open", modal: target, with: { id: "1" }, target: "#modal", confirm: "Open it?"
        end
      end.to_s

      expect(html).to include('hx-confirm="Open it?"')
      expect(html).to include("hx-get=")
    end
  end

  describe "standalone swap:/target: without an interaction kwarg" do
    it "passes a standalone target: through as HTML chrome untouched" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          a "Docs", href: "/docs", target: "_blank"
        end
      end.to_s

      expect(html).to include('target="_blank"')
      expect(html).not_to include("hx-target")
    end

    it "passes a standalone swap: through as chrome after warning" do
      allow(Weft.logger).to receive(:warn)
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div swap: :fill
        end
      end.to_s

      expect(html).to include('swap="fill"')
      expect(html).not_to include("hx-swap")
      expect(Weft.logger).to have_received(:warn).with(/swap/)
    end

    it "warns only once per component class for standalone swap:" do
      allow(Weft.logger).to receive(:warn)
      klass = component_class
      described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div swap: :fill
          div swap: :append
        end
      end.to_s

      expect(Weft.logger).to have_received(:warn).once
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1, "item_id" => 5 }) do
        insert_tag(outer) do
          insert_tag(inner) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 3, "item_id" => 9 }) do
        insert_tag(outer) do
          insert_tag(inner) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Load", loads: target, with: { shipment_id: "42" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/shipment_summary?shipment_id=42"')
    end

    it "generates hx-swap from swap symbol" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).to include('hx-swap="innerHTML"')
    end

    it "generates hx-target from CSS selector string" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tooltip-zone"
        end
      end.to_s

      expect(html).to include('hx-target="#tooltip-zone"')
    end

    it "generates hx-target from :self symbol" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div loads: target, with: { shipment_id: "1" },
              swap: :fill, target: :self
        end
      end.to_s

      expect(html).to include('hx-target="this"')
    end

    it "generates hx-target from Arbre element reference" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div loads: target, with: { shipment_id: "1" },
              swap: :fill, target: :self, trigger: :hover
        end
      end.to_s

      expect(html).to include('hx-trigger="mouseenter once"')
    end

    it "omits hx-trigger when trigger: is not provided" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Load", loads: target, with: { shipment_id: "1" },
                         swap: :fill, target: "#tip"
        end
      end.to_s

      expect(html).not_to include("hx-trigger")
    end

    it "defaults with: to nearest component attrs when omitted" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 77 }) do
        insert_tag(klass) do
          div loads: target, swap: :fill, target: :self
        end
      end.to_s

      expect(html).to include('hx-get="/_components/shipment_summary?order_id=77"')
    end

    it "keeps hand-offs out of the defaulted with: params" do
      target = target_class
      klass = Class.new(Weft::Component) do
        def self.name = "HandedHost"
        param :order_id
        receives :order
      end
      handed = Struct.new(:id).new(3)
      html = described_class.new({}, nil, wire_params: { "order_id" => 77 }) do
        insert_tag(klass, order: handed) do
          div loads: target, swap: :fill, target: :self
        end
      end.to_s

      expect(html).to include('hx-get="/_components/shipment_summary?order_id=77"')
      expect(html).not_to include("struct")
    end

    it "preserves other attributes alongside loads: attrs" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Load", loads: target, target: "#tip"
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /swap/)
    end

    it "raises when target: is missing" do
      target = target_class
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Load", loads: target, swap: :fill
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /target/)
    end
  end

  describe "push_url: kwarg" do
    it "generates hx-push-url with string value" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Filter", action: :advance, push_url: "/orders?status=shipped"
        end
      end.to_s

      expect(html).to include('hx-push-url="/orders?status=shipped"')
      expect(html).to include("hx-post=")
    end

    it "generates hx-push-url with true" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Load", loads: target, with: { id: "1" },
                         swap: :fill, target: "#panel",
                         push_url: "/items/1"
        end
      end.to_s

      expect(html).to include('hx-push-url="/items/1"')
      expect(html).to include("hx-get=")
    end
  end

  describe "load-target routability lint" do
    let(:unroutable_class) do
      Class.new(Weft::Component) do
        def self.name = "EmbeddedOnlyPane"

        def build(attributes = {})
          super
          span "pane"
        end
      end
    end

    it "raises when a loads: target is not routable" do
      target = unroutable_class
      klass = component_class

      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Load", loads: target, swap: :fill, target: "#pane"
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /EmbeddedOnlyPane.*routable!/m)
    end

    it "raises when a preset's Class target is not routable" do
      Weft.register_preset :lint_probe, trigger: :click, swap: :fill, target: :self
      target = unroutable_class
      klass = component_class

      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Load", lint_probe: target
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /lint_probe.*EmbeddedOnlyPane.*routable!/m)
    end

    it "raises when navigate: would re-fetch a component marked non-routable" do
      klass = Class.new(Weft::Component) do
        def self.name = "DependentPanel"
        param :status
        dependent!

        def build(attributes = {})
          super
          button "All", navigate: { status: nil }
        end
      end

      expect do
        described_class.new({}, nil, wire_params: { "status" => "hot" }) do
          insert_tag(klass)
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /DependentPanel.*not routable/m)
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div test_short: target, with: { item_id: "1" }, target: :self
        end
      end.to_s

      expect(html).to include('hx-trigger="mouseenter once"')
    end

    it "allows user trigger: to override preset trigger" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Nope", test_short: target, with: { item_id: "1" }
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /target/)
    end

    it "passes through unregistered kwargs without expansion" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Normal", data_foo: "bar"
        end
      end.to_s

      expect(html).not_to include("hx-get")
    end

    it "preserves other attributes alongside preset attrs" do
      target = target_class
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 42 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Go", test_url: "/x", target: "#other", swap: :outer_html
        end
      end.to_s

      expect(html).to include('hx-target="#other"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "does not treat a String value for an unregistered kwarg name as a preset" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
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
      described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          div({ name => target, with: { id: "1" } }.merge(kwargs))
        end
      end.to_s
    end

    it "tooltip: hover + fill" do
      html = render_with_preset(:tooltip, target: "#tip")

      expect(html).to include('hx-trigger="mouseenter once"')
      expect(html).to include('hx-swap="innerHTML"')
    end

    it "inline_expand: click-once + after" do
      html = render_with_preset(:inline_expand, target: "closest tr")

      expect(html).to include('hx-swap="afterend"')
      expect(html).to include('hx-trigger="click once"')
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
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Retry", retry: "/_components/order_header?order_id=1"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header?order_id=1"')
      expect(html).to include('hx-swap="outerHTML"')
      expect(html).to include('hx-target="closest .weft-error"')
      expect(html).to include('hx-trigger="click"')
    end

    it "reopen_stream: click + outerHTML + closest [sse-swap], hx-get to the given URL" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Resume live updates", reopen_stream: "/_components/order_header?order_id=1"
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header?order_id=1"')
      expect(html).to include('hx-swap="outerHTML"')
      expect(html).to include('hx-target="closest [sse-swap]"')
      expect(html).to include('hx-trigger="click"')
    end
  end

  describe "loud failures for unresolvable Weft kwargs" do
    it "raises on an action: Symbol no enclosing component declares" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Advance", action: :advnace
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /advnace/)
    end

    it "raises on a non-Hash navigate: value" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Next", navigate: "/orders"
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /navigate/)
    end

    it "raises on navigate: outside any component" do
      expect do
        described_class.new({}, nil, wire_params: {}) do
          button "Next", navigate: { page: 2 }
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /component/)
    end

    it "raises on a navigate: key that is not a wire param of the navigated component" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Next", navigate: { page: 2 }
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /page.*wire param/m)
    end

    it "accepts navigate: keys declared as params on a class ancestor" do
      sub = Class.new(component_class) do
        def self.name = "SubHeader"
      end
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(sub) do
          button "Next", navigate: { order_id: 2 }
        end
      end.to_s

      expect(html).to include("hx-get=")
    end

    it "accepts nil values on declared navigate: keys (the drop-a-param idiom)" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Reset", navigate: { order_id: nil }
        end
      end.to_s

      expect(html).to include('hx-get="/_components/order_header"')
    end

    it "raises on with: without loads: or a preset alongside" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Advance", action: :advance, with: { order_id: 2 }
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /with/)
    end

    it "raises on a standalone with:" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            div with: { order_id: 2 }
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /with/)
    end

    it "raises on a non-Class loads: value" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Load", loads: "ShipmentSummary", swap: :fill, target: :self
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /loads/)
    end

    it "raises on a registered preset name with a non-Class, non-String value" do
      klass = component_class
      expect do
        described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
          insert_tag(klass) do
            button "Tip", tooltip: 5, target: "#tip"
          end
        end.to_s
      end.to raise_error(Weft::InvalidUsage, /tooltip/)
    end

    it "treats nil-valued Weft kwargs as absent, for conditional call sites" do
      klass = component_class
      html = described_class.new({}, nil, wire_params: { "order_id" => 1 }) do
        insert_tag(klass) do
          button "Plain", navigate: nil, loads: nil, tooltip: nil, with: nil
        end
      end.to_s

      expect(html).not_to include("hx-get")
      expect(html).to include("<button")
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
