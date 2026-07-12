# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Component do
  describe "attribute DSL" do
    it "declares attributes with defaults" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :status, default: "active"
      end

      expect(component_class.attributes).to eq(status: { default: "active" })
    end

    it "declares attributes without defaults" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :order_id
      end

      expect(component_class.attributes).to eq(order_id: { default: nil })
    end

    it "accepts an optional type: kwarg" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :page, default: 1, type: :integer
      end

      expect(component_class.attributes[:page]).to eq(default: 1, type: :integer)
    end

    it "accumulates multiple attributes in declaration order" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :order_id
        attribute :status, default: "pending"
      end

      expect(component_class.attributes.keys).to eq(%i[order_id status])
    end

    it "inherits parent attributes in subclasses" do
      parent = Class.new(described_class) do
        def self.name = "BaseCard"
        attribute :status
      end
      child = Class.new(parent) do
        def self.name = "SpecialCard"
        attribute :priority, default: "low"
      end

      expect(child.attributes.keys).to eq(%i[status priority])
      # Parent is unaffected
      expect(parent.attributes.keys).to eq(%i[status])
    end
  end

  describe "weft_id" do
    it "derives ID from class name and primary attribute value" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
        attribute :status
      end

      ctx = Arbre::Context.new do
        insert_tag(component_class, status: "shipped")
      end
      component = ctx.children.first

      expect(component.weft_id).to eq("stat-card-shipped")
    end

    it "uses class name alone when no attributes are declared" do
      component_class = Class.new(described_class) do
        def self.name = "GlobalStats"
      end

      ctx = Arbre::Context.new do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_id).to eq("global-stats")
    end

    it "handles namespaced class names" do
      component_class = Class.new(described_class) do
        def self.name = "Oms::OrderHeader"
        attribute :order_id
      end

      ctx = Arbre::Context.new do
        insert_tag(component_class, order_id: 42)
      end
      component = ctx.children.first

      expect(component.weft_id).to eq("oms-order-header-42")
    end
  end

  describe "resolved_component_path" do
    it "derives path from class name using the default component_path proc" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
      end

      expect(component_class.resolved_component_path).to eq("/_components/stat_card")
    end

    it "auto-derives namespace from module nesting" do
      component_class = Class.new(described_class) do
        def self.name = "Oms::OrderHeader"
      end

      expect(component_class.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "strips a trailing 'Component' suffix from the class name" do
      component_class = Class.new(described_class) do
        def self.name = "Oms::OrderHeaderComponent"
      end

      expect(component_class.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "uses class-level component_path string override" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
        self.component_path = "/custom/stats"
      end

      expect(component_class.resolved_component_path).to eq("/custom/stats")
    end

    it "uses class-level component_path proc override" do
      component_class = Class.new(described_class) do
        def self.name = "Oms::OrderHeader"
        self.component_path = ->(klass) { "/api/#{klass.name.split('::').last.downcase}" }
      end

      expect(component_class.resolved_component_path).to eq("/api/orderheader")
    end

    it "inherits component_path proc from parent and resolves with child class" do
      parent = Class.new(described_class) do
        def self.name = "Oms::Base"
        self.component_path = lambda { |klass|
          component_name = klass.name.split("::").last.underscore
          "/_components/oms/#{component_name}"
        }
      end
      child = Class.new(parent) do
        def self.name = "Oms::OrderHeader"
      end

      expect(child.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "raises a helpful error for a routable class whose name has no usable stem" do
      component_class = Class.new(described_class) do
        def self.name = "Foo::Component"
        attribute :id
      end

      expect { component_class.resolved_component_path }.
        to raise_error(Weft::InvalidDefinition, /no resolvable default component path.*abstract!/m)
    end

    it "does not guard a non-routable class with an empty stem (it never routes)" do
      component_class = Class.new(described_class) do
        def self.name = "Foo::Component"
      end

      expect { component_class.resolved_component_path }.not_to raise_error
    end
  end

  describe "inherited hook and registry" do
    it "auto-registers subclasses with the global registry" do
      component_class = Class.new(described_class) do
        def self.name = "AutoRegistered"
      end

      expect(Weft.registry.components).to include(component_class)
    end

    it "auto-registers grandchildren" do
      parent = Class.new(described_class) do
        def self.name = "BaseComponent"
      end
      grandchild = Class.new(parent) do
        def self.name = "SpecificComponent"
      end

      expect(Weft.registry.components).to include(parent, grandchild)
    end

    it "registers abstract classes harmlessly" do
      abstract = Class.new(described_class) do
        def self.name = "AbstractBase"
      end

      expect(Weft.registry.components).to include(abstract)
    end
  end

  describe ".stale?" do
    it "is not stale for an anonymous/stubbed class whose name does not resolve" do
      component_class = Class.new(described_class) { def self.name = "GhostCard" }
      expect(component_class.stale?).to be(false)
    end

    it "is not stale for a class whose constant resolves to itself" do
      stub_const("LiveCard", Class.new(described_class))
      expect(LiveCard.stale?).to be(false)
    end

    it "is stale once its constant is reassigned to a different class (reload)" do
      stub_const("ReloadCard", Class.new(described_class))
      original = ReloadCard
      stub_const("ReloadCard", Class.new(described_class))

      expect(original.stale?).to be(true)
      expect(ReloadCard.stale?).to be(false)
    end
  end

  describe ".routable?" do
    it "is routable when attributes are declared" do
      component_class = Class.new(described_class) do
        def self.name = "WithAttrs"
        attribute :status
      end

      expect(component_class).to be_routable
    end

    it "is routable when actions are declared" do
      component_class = Class.new(described_class) do
        def self.name = "WithAction"
        performs(:go) { nil }
      end

      expect(component_class).to be_routable
    end

    it "is routable when refresh triggers are declared" do
      component_class = Class.new(described_class) do
        def self.name = "WithRefresh"
        refreshes every: 10
      end

      expect(component_class).to be_routable
    end

    it "is routable when push config is declared" do
      component_class = Class.new(described_class) do
        def self.name = "WithPush"
        pushes every: 5
      end

      expect(component_class).to be_routable
    end

    it "is not routable when bare (no attrs, verbs, or declarations)" do
      component_class = Class.new(described_class) do
        def self.name = "BareComponent"
      end

      expect(component_class).not_to be_routable
    end

    it "is not routable with only triggers (response modifier, not addressable)" do
      component_class = Class.new(described_class) do
        def self.name = "OnlyTriggers"
        triggers "some-event"
      end

      expect(component_class).not_to be_routable
    end

    it "is not routable with only includes (response modifier, not addressable)" do
      target = Class.new(described_class) { def self.name = "IncTarget2" }
      component_class = Class.new(described_class) do
        def self.name = "OnlyIncludes"
      end
      component_class.includes(target)

      expect(component_class).not_to be_routable
    end

    it "is routable when parent is routable (inherits attributes)" do
      parent = Class.new(described_class) do
        def self.name = "RoutableParent"
        attribute :id
      end
      child = Class.new(parent) do
        def self.name = "ChildOfRoutable"
      end

      expect(child).to be_routable
    end

    describe "abstract! and routable! overrides" do
      it "abstract! makes a routable class non-routable" do
        component_class = Class.new(described_class) do
          def self.name = "AbstractedComponent"
          attribute :id
          abstract!
        end

        expect(component_class).not_to be_routable
      end

      it "abstract! does not percolate — concrete subclass is routable again" do
        parent = Class.new(described_class) do
          def self.name = "AbstractParent"
          attribute :id
          abstract!
        end
        child = Class.new(parent) do
          def self.name = "ConcreteChild"
        end

        expect(parent).not_to be_routable
        expect(child).to be_routable
      end

      it "routable! forces routability when inference says no" do
        component_class = Class.new(described_class) do
          def self.name = "ForcedRoutable"
          routable!
        end

        expect(component_class).to be_routable
      end

      it "routable! does not percolate to subclasses" do
        parent = Class.new(described_class) do
          def self.name = "ForcedParent"
          routable!
        end
        child = Class.new(parent) do
          def self.name = "BareChild"
        end

        expect(parent).to be_routable
        expect(child).not_to be_routable
      end
    end
  end

  describe "performs DSL" do
    it "registers a named action with a callable" do
      component_class = Class.new(described_class) do
        def self.name = "ActionTest"
        attribute :order_id
        performs(:advance) { nil }
      end

      action = component_class.actions[%i[advance post]]
      expect(action).to be_a(Weft::Action)
      expect(action.name).to eq(:advance)
      expect(action.method).to eq(:post)
      expect(action.renders).to eq(component_class)
    end

    it "registers a nameless action" do
      component_class = Class.new(described_class) do
        def self.name = "RootAction"
        performs(method: :get) { nil }
      end

      action = component_class.actions[[nil, :get]]
      expect(action).not_to be_nil
      expect(action).to be_nameless
    end

    it "supports method:, swap:, and target: kwargs" do
      component_class = Class.new(described_class) do
        def self.name = "CustomAction"
        performs(:remove, method: :delete, swap: :delete, target: "#parent") { nil }
      end

      action = component_class.actions[%i[remove delete]]
      expect(action.method).to eq(:delete)
      expect(action.swap).to eq(:delete)
    end

    it "looks up actions by name via action_for" do
      component_class = Class.new(described_class) do
        def self.name = "LookupTest"
        performs(:advance) { nil }
        performs(:cancel, method: :delete) { nil }
      end

      expect(component_class.action_for(:advance).name).to eq(:advance)
      expect(component_class.action_for(:cancel).name).to eq(:cancel)
      expect(component_class.action_for(:nonexistent)).to be_nil
    end

    it "inherits actions from parent classes" do
      parent = Class.new(described_class) do
        def self.name = "ParentAction"
        performs(:shared) { nil }
      end
      child = Class.new(parent) do
        def self.name = "ChildAction"
        performs(:own) { nil }
      end

      expect(child.action_for(:shared)).not_to be_nil
      expect(child.action_for(:own)).not_to be_nil
      expect(parent.action_for(:own)).to be_nil
    end
  end

  describe "refreshes DSL" do
    it "generates polling htmx attributes with every:" do
      component_class = Class.new(described_class) do
        def self.name = "PollingCard"
        attribute :status, default: "all"
        refreshes every: 10
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-get="/_components/polling_card?status=shipped"')
      expect(html).to include('hx-trigger="every 10s"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "accepts an ActiveSupport duration for every:" do
      component_class = Class.new(described_class) do
        def self.name = "DurationCard"
        attribute :status, default: "all"
        refreshes every: 5.seconds
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 5s"')
    end

    it "renders sub-second every: values in milliseconds" do
      component_class = Class.new(described_class) do
        def self.name = "FastCard"
        attribute :status, default: "all"
        refreshes every: 0.6
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 600ms"')
    end

    it "renders fractional multi-second every: values in milliseconds" do
      component_class = Class.new(described_class) do
        def self.name = "FractionalCard"
        attribute :status, default: "all"
        refreshes every: 2.5
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 2500ms"')
    end

    it "warns and rounds every: values below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(described_class) do
        def self.name = "TooFastCard"
        attribute :status, default: "all"
        refreshes every: 0.0000001
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 1ms"')
      expect(Weft.logger).to have_received(:warn).with(/below the 1ms floor/)
    end

    it "generates event-driven htmx attributes with on:" do
      component_class = Class.new(described_class) do
        def self.name = "EventCard"
        attribute :driver_id
        refreshes on: "delivery-completed"
      end

      html = component_class.render(driver_id: "42")

      expect(html).to include('hx-get="/_components/event_card?driver_id=42"')
      expect(html).to include('hx-trigger="delivery-completed from:body"')
      expect(html).to include('hx-swap="outerHTML"')
    end

    it "combines multiple refresh declarations into one hx-trigger" do
      component_class = Class.new(described_class) do
        def self.name = "CombinedCard"
        attribute :id
        refreshes every: 30
        refreshes on: "item-updated"
      end

      html = component_class.render(id: "1")

      expect(html).to include('hx-trigger="every 30s, item-updated from:body"')
    end

    it "does not set refresh attributes when no refreshes declared" do
      component_class = Class.new(described_class) do
        def self.name = "StaticCard"
        attribute :label
      end

      html = component_class.render(label: "test")

      expect(html).not_to include("hx-get")
      expect(html).not_to include("hx-trigger")
    end

    it "inherits refresh declarations from parent classes" do
      parent = Class.new(described_class) do
        def self.name = "RefreshBase"
        refreshes every: 15
      end
      child = Class.new(parent) do
        def self.name = "RefreshChild"
        attribute :id
        refreshes on: "updated"
      end

      html = child.render(id: "1")

      expect(html).to include("every 15s")
      expect(html).to include("updated from:body")
    end

    it "omits nil attrs from the refresh URL" do
      component_class = Class.new(described_class) do
        def self.name = "NilAttrCard"
        attribute :status
        attribute :label, default: "test"
        refreshes every: 5
      end

      html = component_class.render(label: "hello")

      expect(html).to include('hx-get="/_components/nil_attr_card?label=hello"')
      expect(html).not_to include("status=")
    end
  end

  describe "pushes DSL" do
    it "generates SSE htmx attributes with every:" do
      component_class = Class.new(described_class) do
        def self.name = "PushCard"
        attribute :order_id

        def build(attributes = {})
          super
          span "content"
        end
      end
      component_class.pushes every: 5

      html = component_class.render(order_id: "42")

      expect(html).to include('hx-ext="sse"')
      expect(html).to include('sse-connect="/_components/push_card/_stream?order_id=42"')
      expect(html).to include('sse-swap="push-card-42"')
      expect(html).to include('hx-swap="innerHTML"')
    end

    it "builds the stream URL with the configured stream_suffix" do
      original = Weft.configuration.stream_suffix
      Weft.configuration.stream_suffix = "sse"
      component_class = Class.new(described_class) do
        def self.name = "SuffixPushCard"
        attribute :order_id
        pushes every: 5
      end

      html = component_class.render(order_id: "42")

      expect(html).to include('sse-connect="/_components/suffix_push_card/sse?order_id=42"')
    ensure
      Weft.configuration.stream_suffix = original
    end

    it "does not set SSE attributes when no pushes declared" do
      component_class = Class.new(described_class) do
        def self.name = "StaticCard"
        attribute :label
      end

      html = component_class.render(label: "test")

      expect(html).not_to include("hx-ext")
      expect(html).not_to include("sse-connect")
      expect(html).not_to include("sse-swap")
    end

    it "inherits push config from parent classes" do
      parent = Class.new(described_class) do
        def self.name = "PushBase"
        pushes every: 10
      end
      child = Class.new(parent) do
        def self.name = "PushChild"
        attribute :id

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
      component_class = Class.new(described_class) do
        def self.name = "FastTicker"
        attribute :label
        pushes every: 0.5
      end

      expect(component_class.push_config).to eq(every: 0.5)
    end

    it "warns and rounds a pushes interval below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(described_class) do
        def self.name = "TooFastTicker"
        attribute :label
        pushes every: 0.0000001
      end

      expect(component_class.push_config).to eq(every: 0.001)
      expect(Weft.logger).to have_received(:warn).with(/below the 1ms floor/)
    end

    it "stores push_config with the interval" do
      component_class = Class.new(described_class) do
        def self.name = "ConfigTest"
        pushes every: 15
      end

      expect(component_class.push_config).to eq(every: 15)
    end

    it "returns nil push_config when no pushes declared" do
      component_class = Class.new(described_class) do
        def self.name = "NoPush"
      end

      expect(component_class.push_config).to be_nil
    end

    it "uses the DOM ID as the SSE event name (sse-swap value)" do
      component_class = Class.new(described_class) do
        def self.name = "Oms::ShipmentCard"
        attribute :order_id
        pushes every: 5
      end

      html = component_class.render(order_id: "99")

      expect(html).to include('sse-swap="oms-shipment-card-99"')
    end

    it "omits nil attrs from the stream URL" do
      component_class = Class.new(described_class) do
        def self.name = "NilPush"
        attribute :status
        attribute :label, default: "test"
        pushes every: 5
      end

      html = component_class.render(label: "hello")

      expect(html).to include('sse-connect="/_components/nil_push/_stream?label=hello"')
      expect(html).not_to include("status=")
    end
  end

  describe "includes DSL" do
    it "stores inclusions with component class" do
      included = Class.new(described_class) { def self.name = "IncTarget" }
      component_class = Class.new(described_class) do
        def self.name = "IncSource"
      end
      component_class.includes(included)

      expect(component_class.inclusions.size).to eq(1)
      expect(component_class.inclusions.first[:component_class]).to eq(included)
    end

    it "stores optional on: filter" do
      included = Class.new(described_class) { def self.name = "IncFiltered" }
      component_class = Class.new(described_class) do
        def self.name = "IncFilterSource"
      end
      component_class.includes(included, on: :advance)

      expect(component_class.inclusions.first[:on]).to eq(:advance)
    end

    it "stores optional block for attr mapping" do
      included = Class.new(described_class) { def self.name = "IncMapped" }
      component_class = Class.new(described_class) do
        def self.name = "IncMapSource"
      end
      component_class.includes(included) { |attrs| { id: attrs[:order_id] } }

      expect(component_class.inclusions.first[:block]).to be_a(Proc)
    end

    it "inherits inclusions from parent classes" do
      included = Class.new(described_class) { def self.name = "InheritedInc" }
      parent = Class.new(described_class) do
        def self.name = "IncParent"
      end
      parent.includes(included)
      child = Class.new(parent) do
        def self.name = "IncChild"
      end

      expect(child.inclusions.size).to eq(1)
      expect(parent.inclusions.size).to eq(1)
    end

    it "accumulates multiple inclusions" do
      inc_a = Class.new(described_class) { def self.name = "IncA" }
      inc_b = Class.new(described_class) { def self.name = "IncB" }
      component_class = Class.new(described_class) do
        def self.name = "MultiInc"
      end
      component_class.includes(inc_a)
      component_class.includes(inc_b)

      expect(component_class.inclusions.size).to eq(2)
    end
  end

  describe "dismisses DSL" do
    it "registers a performs action with swap: :delete" do
      component_class = Class.new(described_class) do
        def self.name = "Dismissable"
        dismisses(:close) { nil }
      end

      action = component_class.actions[%i[close delete]]
      expect(action).to be_a(Weft::Action)
      expect(action.swap).to eq(:delete)
      expect(action.method).to eq(:delete)
    end

    it "works without a block" do
      component_class = Class.new(described_class) do
        def self.name = "SimpleDismiss"
        dismisses :remove
      end

      action = component_class.actions[%i[remove delete]]
      expect(action).not_to be_nil
      expect(action.callable).to be_nil
    end

    it "supports nameless form (DELETE at root path)" do
      component_class = Class.new(described_class) do
        def self.name = "NamelessDismiss"
        dismisses
      end

      action = component_class.actions[[nil, :delete]]
      expect(action).not_to be_nil
      expect(action.swap).to eq(:delete)
    end

    it "generates htmx delete attributes via action: kwarg" do
      component_class = Class.new(described_class) do
        def self.name = "DismissRender"
        attribute :item_id
        dismisses :close

        def build(attributes = {})
          super
          button "X", action: :close
        end
      end

      html = component_class.render(item_id: "7")

      expect(html).to include('hx-delete="/_components/dismiss_render/close"')
      expect(html).to include('hx-swap="delete"')
    end
  end

  describe "#weft_url" do
    it "returns the component path with current attrs" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        attribute :status
        attribute :page, default: 1
      end

      ctx = Weft::Context.new({}, nil) { insert_tag(component_class, status: "shipped", page: 2) }
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?status=shipped&page=2")
    end

    it "overrides specific attrs" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        attribute :status
        attribute :page, default: 1
      end

      ctx = Weft::Context.new({}, nil) { insert_tag(component_class, status: "shipped", page: 2) }
      component = ctx.children.first

      expect(component.weft_url(page: 3)).to eq("/_components/panel?status=shipped&page=3")
    end

    it "omits nil values from the URL" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        attribute :status
        attribute :page, default: 1
      end

      ctx = Weft::Context.new({}, nil) { insert_tag(component_class, status: nil, page: 1) }
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?page=1")
    end
  end

  describe ".render" do
    it "renders a component to an HTML string outside any DSL context" do
      component_class = Class.new(described_class) do
        def self.name = "Renderable"
        attribute :status

        def build(attributes = {})
          super
          div { text_node "status=#{attrs.status}" }
        end
      end

      html = component_class.render(status: "shipped")

      expect(html).to include("status=shipped")
      expect(html).to include("<div")
    end

    it "returns a bare fragment, not a full HTML document" do
      component_class = Class.new(described_class) do
        def self.name = "SimpleRenderable"
      end

      html = component_class.render

      expect(html).not_to include("<!DOCTYPE")
      expect(html).not_to include("<html")
    end
  end

  describe "build" do
    it "extracts declared attributes from the arbre attributes hash" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :status
        attribute :count, default: 0

        def build(attributes = {})
          super
          div { text_node "status=#{attrs[:status]}, count=#{attrs[:count]}" }
        end
      end

      html = Arbre::Context.new { insert_tag(component_class, status: "active", count: 5) }.to_s

      expect(html).to include("status=active, count=5")
    end

    it "applies defaults for missing attributes" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        attribute :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{attrs[:status]}" }
        end
      end

      html = Arbre::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("status=pending")
    end

    it "sets the DOM id from weft_id" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
        attribute :status
      end

      ctx = Arbre::Context.new { insert_tag(component_class, status: "shipped") }
      component = ctx.children.first

      expect(component.id).to eq("stat-card-shipped")
    end

    it "does not mutate the caller's attributes hash" do
      component_class = Class.new(described_class) do
        def self.name = "NonMutating"
        attribute :status
      end

      shared = { status: "shipped", class: "big" }
      Arbre::Context.new { insert_tag(component_class, **shared) }.to_s

      expect(shared).to eq(status: "shipped", class: "big")
    end

    it "renders as a div by default" do
      component_class = Class.new(described_class) do
        def self.name = "SimpleCard"

        def build(attributes = {})
          super
          span "hello"
        end
      end

      html = Arbre::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("<div")
      expect(html).to include("<span>hello</span>")
    end
  end

  describe "recovers DSL" do
    # The gem-default `recovers from: StandardError, with: :error_component` on
    # Weft::Component is inherited by every subclass. Tests in this block assert
    # against subclass-own entries (the first N of recoveries), with the gem
    # default trailing as inherited.
    it "stores a single entry with from:, with: nil, and the block" do
      handler = ->(_attrs, _error) { { message: "oops" } }
      component_class = Class.new(described_class) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable, &handler)

      expect(component_class.recoveries.first).to eq(
        from: Weft::Unprocessable, with: nil, block: handler
      )
    end

    it "stores an entry with an explicit with: target" do
      target = Class.new(described_class) do
        def self.name = "ErrorTarget"
      end
      component_class = Class.new(described_class) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable, with: target)

      expect(component_class.recoveries.first).to eq(
        from: Weft::Unprocessable, with: target, block: nil
      )
    end

    it "accepts a Symbol with: for configuration-time resolution" do
      component_class = Class.new(described_class) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: StandardError, with: :error_component)

      expect(component_class.recoveries.first[:with]).to eq(:error_component)
    end

    it "accumulates multiple recovers calls as separate entries in declaration order" do
      component_class = Class.new(described_class) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable)
      component_class.recovers(from: Weft::Unauthorized)

      from_values = component_class.recoveries.map { |e| e[:from] }.take(2)
      expect(from_values).to eq([Weft::Unprocessable, Weft::Unauthorized])
    end

    it "raises ArgumentError when from: is missing" do
      component_class = Class.new(described_class) do
        def self.name = "Recoverable"
      end

      expect { component_class.recovers }.to raise_error(ArgumentError, /:from/)
    end

    it "inherits recovers entries from parent class" do
      parent = Class.new(described_class) do
        def self.name = "ParentRecover"
      end
      parent.recovers(from: Weft::Unprocessable)
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end

      from_values = child.recoveries.map { |e| e[:from] }
      expect(from_values).to start_with(Weft::Unprocessable)
    end

    it "child entries precede parent entries in the chain (most-specific first)" do
      parent = Class.new(described_class) do
        def self.name = "ParentRecover"
      end
      parent.recovers(from: Weft::Unprocessable)
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end
      child.recovers(from: Weft::Unauthorized)

      from_values = child.recoveries.map { |e| e[:from] }.take(2)
      expect(from_values).to eq([Weft::Unauthorized, Weft::Unprocessable])
    end

    it "child entries do not leak into the parent class" do
      parent = Class.new(described_class) do
        def self.name = "ParentRecover"
      end
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end
      child.recovers(from: Weft::Unprocessable)

      expect(parent.recoveries.map { |e| e[:from] }).not_to include(Weft::Unprocessable)
    end

    it "every Weft::Component subclass inherits a gem-default StandardError entry targeting :error_component" do
      component_class = Class.new(described_class) do
        def self.name = "PlainComponent"
      end

      gem_default = component_class.recoveries.last
      expect(gem_default).to eq(from: StandardError, with: :error_component, block: nil)
    end

    it "inherits a gem-default Weft::NotFound entry targeting :not_found_component, ahead of the StandardError entry" do
      component_class = Class.new(described_class) do
        def self.name = "PlainNotFoundComponent"
      end

      entries = component_class.recoveries
      not_found_entry = entries.find { |e| e[:from] == Weft::NotFound }
      expect(not_found_entry).to eq(from: Weft::NotFound, with: :not_found_component, block: nil)
      # Ordered before the StandardError gem-default so a component-context
      # NotFound resolves to the 404 body, not the generic error component.
      expect(entries.index(not_found_entry)).to be < entries.index(entries.last)
      expect(entries.last).to eq(from: StandardError, with: :error_component, block: nil)
    end
  end

  describe ".recovery_for" do
    it "returns the gem-default StandardError entry when no user entry matches" do
      component_class = Class.new(described_class) do
        def self.name = "NoRecover"
      end
      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:with]).to eq(:error_component)
    end

    it "resolves a component-context Weft::NotFound to the :not_found_component gem-default" do
      component_class = Class.new(described_class) do
        def self.name = "NotFoundResolver"
      end
      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:not_found_component)
    end

    it "returns nil for an exception outside StandardError's hierarchy" do
      component_class = Class.new(described_class) do
        def self.name = "NoRecover"
      end
      expect(component_class.recovery_for(Exception.new)).to be_nil
    end

    it "matches by Class (subclass-inclusive)" do
      component_class = Class.new(described_class) do
        def self.name = "ClassMatcher"
      end
      component_class.recovers(from: Weft::HTTPError)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(Weft::HTTPError)
    end

    it "matches a foreign exception class directly" do
      foreign_error = Class.new(StandardError)
      component_class = Class.new(described_class) do
        def self.name = "ForeignMatcher"
      end
      component_class.recovers(from: foreign_error)

      entry = component_class.recovery_for(foreign_error.new)
      expect(entry[:from]).to eq(foreign_error)
    end

    it "matches by Integer status on HTTPError" do
      component_class = Class.new(described_class) do
        def self.name = "IntMatcher"
      end
      component_class.recovers(from: 404)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(404)
    end

    it "treats a non-HTTPError exception as status 500" do
      component_class = Class.new(described_class) do
        def self.name = "Int500Matcher"
      end
      component_class.recovers(from: 500)

      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(500)
    end

    it "does not match a non-HTTPError exception against an unrelated Integer status" do
      component_class = Class.new(described_class) do
        def self.name = "IntMissMatcher"
      end
      component_class.recovers(from: 404)

      # The own Integer-status entry doesn't match StandardError, but the gem-default
      # StandardError entry is still in the chain — so .recovery_for falls through to it.
      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(StandardError)
    end

    it "matches by Range over HTTPError status" do
      component_class = Class.new(described_class) do
        def self.name = "RangeMatcher"
      end
      component_class.recovers(from: 400..499)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(400..499)
    end

    it "treats non-HTTPError exceptions as status 500 for Range matching" do
      component_class = Class.new(described_class) do
        def self.name = "Range500Matcher"
      end
      component_class.recovers(from: 500..599)

      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(500..599)
    end

    it "matches by Array (any element matches)" do
      foreign_error = Class.new(StandardError)
      component_class = Class.new(described_class) do
        def self.name = "ArrayMatcher"
      end
      component_class.recovers(from: [Weft::Forbidden, foreign_error])

      expect(component_class.recovery_for(foreign_error.new)[:from]).to eq(
        [Weft::Forbidden, foreign_error]
      )
      expect(component_class.recovery_for(Weft::Forbidden.new)[:from]).to eq(
        [Weft::Forbidden, foreign_error]
      )
    end

    it "returns first matching entry in chain order" do
      component_class = Class.new(described_class) do
        def self.name = "FirstWins"
      end
      component_class.recovers(from: Weft::HTTPError, with: :first)
      component_class.recovers(from: Weft::NotFound, with: :second)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:first)
    end

    it "subclass entries take precedence over ancestor entries" do
      parent = Class.new(described_class) do
        def self.name = "ParentRecover2"
      end
      parent.recovers(from: StandardError, with: :parent_target)
      child = Class.new(parent) do
        def self.name = "ChildRecover2"
      end
      child.recovers(from: Weft::NotFound, with: :child_target)

      entry = child.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:child_target)
    end
  end

  describe ".resolve_recovery_target" do
    it "returns the with: class directly when it is a Class" do
      target = Class.new
      component_class = Class.new(described_class) do
        def self.name = "ResolverComp"
      end
      entry = { from: StandardError, with: target, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(target)
    end

    it "resolves a Symbol with: through Weft.configuration" do
      component_class = Class.new(described_class) do
        def self.name = "ResolverComp"
      end
      fake_page = Class.new
      allow(Weft.configuration).to receive(:not_found_page).and_return(fake_page)
      entry = { from: StandardError, with: :not_found_page, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(fake_page)
    end

    it "falls back to self when with: is nil" do
      component_class = Class.new(described_class) do
        def self.name = "ResolverComp"
      end
      entry = { from: StandardError, with: nil, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(component_class)
    end
  end
end
