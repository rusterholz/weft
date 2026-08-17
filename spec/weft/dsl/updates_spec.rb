# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Updates do
  describe "refreshes DSL" do
    it "generates polling htmx attributes with every:" do
      component_class = Class.new(Weft::Component) do
        def self.name = "PollingCard"
        param :status, default: "all"
        refreshes every: 10
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-get="/_components/polling_card?status=shipped"')
      expect(html).to include('hx-trigger="every 10s"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "accepts an ActiveSupport duration for every:" do
      component_class = Class.new(Weft::Component) do
        def self.name = "DurationCard"
        param :status, default: "all"
        refreshes every: 5.seconds
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 5s"')
    end

    it "renders sub-second every: values in milliseconds" do
      component_class = Class.new(Weft::Component) do
        def self.name = "FastCard"
        param :status, default: "all"
        refreshes every: 0.6
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 600ms"')
    end

    it "renders fractional multi-second every: values in milliseconds" do
      component_class = Class.new(Weft::Component) do
        def self.name = "FractionalCard"
        param :status, default: "all"
        refreshes every: 2.5
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 2500ms"')
    end

    it "warns and rounds every: values below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(Weft::Component) do
        def self.name = "TooFastCard"
        param :status, default: "all"
        refreshes every: 0.0000001
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 1ms"')
      expect(Weft.logger).to have_received(:warn).with(/below the 1ms floor/)
    end

    it "generates event-driven htmx attributes with on:" do
      component_class = Class.new(Weft::Component) do
        def self.name = "EventCard"
        param :driver_id
        refreshes on: "delivery-completed"
      end

      html = component_class.render(driver_id: "42")

      expect(html).to include('hx-get="/_components/event_card?driver_id=42"')
      expect(html).to include('hx-trigger="delivery-completed from:body"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "combines multiple refresh declarations into one hx-trigger" do
      component_class = Class.new(Weft::Component) do
        def self.name = "CombinedCard"
        param :id
        refreshes every: 30
        refreshes on: "item-updated"
      end

      html = component_class.render(id: "1")

      expect(html).to include('hx-trigger="every 30s, item-updated from:body"')
    end

    it "does not set refresh attributes when no refreshes declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StaticCard"
        param :label
      end

      html = component_class.render(label: "test")

      expect(html).not_to include("hx-get")
      expect(html).not_to include("hx-trigger")
    end

    it "inherits refresh declarations from parent classes" do
      parent = Class.new(Weft::Component) do
        def self.name = "RefreshBase"
        refreshes every: 15
      end
      child = Class.new(parent) do
        def self.name = "RefreshChild"
        param :id
        refreshes on: "updated"
      end

      html = child.render(id: "1")

      expect(html).to include("every 15s")
      expect(html).to include("updated from:body")
    end

    it "omits nil params from the refresh URL" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NilAttrCard"
        param :status
        param :label, default: "test"
        refreshes every: 5
      end

      html = component_class.render(label: "hello")

      expect(html).to include('hx-get="/_components/nil_attr_card?label=hello"')
      expect(html).not_to include("status=")
    end
  end

  describe "pushes DSL" do
    let(:push_card) do
      Class.new(Weft::Component) do
        def self.name = "PushCard"
        param :order_id
        identifies_by :order_id
        pushes every: 5

        def build(attributes = {})
          super
          span "content"
        end
      end
    end

    it "generates SSE htmx attributes with every:" do
      html = push_card.render(order_id: "42")

      expect(html).to include('hx-ext="sse"')
      expect(html).to include('sse-connect="/_components/push_card/_stream?order_id=42"')
      expect(html).to include('sse-swap="push-card-42"')
      expect(html).to include('sse-close="weft:close"')
      expect(html).to include('hx-swap="innerHTML"')
    end

    it "builds the stream URL with the configured stream_suffix" do
      original = Weft.configuration.stream_suffix
      Weft.configuration.stream_suffix = "sse"
      component_class = Class.new(Weft::Component) do
        def self.name = "SuffixPushCard"
        param :order_id
        pushes every: 5
      end

      html = component_class.render(order_id: "42")

      expect(html).to include('sse-connect="/_components/suffix_push_card/sse?order_id=42"')
    ensure
      Weft.configuration.stream_suffix = original
    end

    it "does not set SSE attributes when no pushes declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StaticCard"
        param :label
      end

      html = component_class.render(label: "test")

      expect(html).not_to include("hx-ext")
      expect(html).not_to include("sse-connect")
      expect(html).not_to include("sse-swap")
      expect(html).not_to include("sse-close")
    end

    it "inherits push config from parent classes" do
      parent = Class.new(Weft::Component) do
        def self.name = "PushBase"
        pushes every: 10
      end
      child = Class.new(parent) do
        def self.name = "PushChild"
        param :id

        def build(attributes = {})
          super
          span "child content"
        end
      end

      html = child.render(id: "7")

      expect(html).to include('hx-ext="sse"')
      expect(html).to include('sse-connect="/_components/push_child/_stream?id=7"')
    end

    it "keeps a fractional pushes interval fractional" do
      component_class = Class.new(Weft::Component) do
        def self.name = "FastTicker"
        param :label
        pushes every: 0.5
      end

      expect(component_class.push_config).to eq(every: 0.5)
    end

    it "warns and rounds a pushes interval below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(Weft::Component) do
        def self.name = "TooFastTicker"
        param :label
        pushes every: 0.0000001
      end

      expect(component_class.push_config).to eq(every: 0.001)
      expect(Weft.logger).to have_received(:warn).with(/below the 1ms floor/)
    end

    it "stores push_config with the interval" do
      component_class = Class.new(Weft::Component) do
        def self.name = "ConfigTest"
        pushes every: 15
      end

      expect(component_class.push_config).to eq(every: 15)
    end

    it "stores a declared attempts budget in push_config" do
      component_class = Class.new(Weft::Component) do
        def self.name = "BudgetedTicker"
        pushes every: 5, attempts: 5
      end

      expect(component_class.push_config).to eq(every: 5, attempts: 5)
    end

    it "stores a declared immediate: false in push_config" do
      component_class = Class.new(Weft::Component) do
        def self.name = "PatientTicker"
        pushes every: 5, immediate: false
      end

      expect(component_class.push_config).to eq(every: 5, immediate: false)
    end

    it "omits :attempts from push_config when not declared (gem config governs)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "DefaultBudgetTicker"
        pushes every: 5
      end

      expect(component_class.push_config).not_to have_key(:attempts)
    end

    it "inherits a declared attempts budget through push_config" do
      parent = Class.new(Weft::Component) do
        def self.name = "BudgetedBase"
        pushes every: 10, attempts: 2
      end
      child = Class.new(parent) do
        def self.name = "BudgetedChild"
      end

      expect(child.push_config).to eq(every: 10, attempts: 2)
    end

    it "warns and clamps a non-positive attempts budget to 1" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(Weft::Component) do
        def self.name = "ZeroBudgetTicker"
        pushes every: 5, attempts: 0
      end

      expect(component_class.push_config).to eq(every: 5, attempts: 1)
      expect(Weft.logger).to have_received(:warn).with(/attempts/)
    end

    it "warns and clamps a non-integer attempts budget to 1" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(Weft::Component) do
        def self.name = "FractionalBudgetTicker"
        pushes every: 5, attempts: 2.5
      end

      expect(component_class.push_config).to eq(every: 5, attempts: 1)
      expect(Weft.logger).to have_received(:warn).with(/attempts/)
    end

    it "returns nil push_config when no pushes declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NoPush"
      end

      expect(component_class.push_config).to be_nil
    end

    it "uses the DOM ID as the SSE event name (sse-swap value)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Oms::ShipmentCard"
        param :order_id
        identifies_by :order_id
        pushes every: 5
      end

      html = component_class.render(order_id: "99")

      expect(html).to include('sse-swap="oms-shipment-card-99"')
    end

    it "omits nil params from the stream URL" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NilPush"
        param :status
        param :label, default: "test"
        pushes every: 5
      end

      html = component_class.render(label: "hello")

      expect(html).to include('sse-connect="/_components/nil_push/_stream?label=hello"')
      expect(html).not_to include("status=")
    end
  end
end
