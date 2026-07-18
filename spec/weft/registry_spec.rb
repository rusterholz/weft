# frozen_string_literal: true

RSpec.describe Weft::Registry do
  subject(:registry) { described_class.new }

  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "StatCard"
      param :status
    end
  end

  let(:namespaced_class) do
    Class.new(Weft::Component) do
      def self.name = "Oms::OrderHeader"
      param :order_id
    end
  end

  describe "#register" do
    it "stores a component class" do
      registry.register(component_class)
      expect(registry.components).to include(component_class)
    end

    it "is idempotent" do
      registry.register(component_class)
      registry.register(component_class)
      expect(registry.components.count { |c| c == component_class }).to eq(1)
    end
  end

  describe "#components" do
    it "returns all registered classes" do
      registry.register(component_class)
      registry.register(namespaced_class)
      expect(registry.components).to contain_exactly(component_class, namespaced_class)
    end

    it "returns an empty collection when nothing is registered" do
      expect(registry.components).to be_empty
    end
  end

  describe "#lookup" do
    before do
      registry.register(component_class)
      registry.register(namespaced_class)
    end

    it "finds a component by its derived path" do
      expect(registry.lookup("/_components/stat_card")).to eq(component_class)
    end

    it "finds a namespaced component by its derived path" do
      expect(registry.lookup("/_components/oms/order_header")).to eq(namespaced_class)
    end

    it "returns nil for unknown paths" do
      expect(registry.lookup("/_components/nonexistent")).to be_nil
    end

    it "invalidates the index when a new component is registered" do
      expect(registry.lookup("/_components/late_addition")).to be_nil

      late_class = Class.new(Weft::Component) do
        def self.name = "LateAddition"
        param :x
      end
      registry.register(late_class)

      expect(registry.lookup("/_components/late_addition")).to eq(late_class)
    end

    it "does not index a non-routable component" do
      plain = Class.new(Weft::Component) { def self.name = "PlainPanel" }
      registry.register(plain)

      expect(registry.lookup("/_components/plain_panel")).to be_nil
    end
  end

  describe "route collision detection" do
    it "raises when two routable components resolve to the same path" do
      a = Class.new(Weft::Component) do
        def self.name = "Foo"
        param :x
      end
      b = Class.new(Weft::Component) do
        # strips to "Foo" -> same /_components/foo as `a`
        def self.name = "FooComponent"
        param :y
      end
      registry.register(a)
      registry.register(b)

      expect { registry.lookup("/_components/foo") }.to raise_error(
        Weft::InvalidDefinition, %r{Route collision on "/_components/foo".*Foo.*FooComponent}m
      )
    end

    it "raises when two routable pages route at the same path" do
      a = Class.new(Weft::Page) { def self.name = "ReportsPage" }
      b = Class.new(Weft::Page) { def self.name = "Reports" } # both -> /reports
      registry.register_page(a)
      registry.register_page(b)

      expect { registry.match_page("/reports") }.to raise_error(
        Weft::InvalidDefinition, %r{Route collision on "/reports".*Reports}m
      )
    end

    it "raises when a component and a page claim the same path" do
      comp = Class.new(Weft::Component) do
        def self.name = "Dashboard"
        param :x
        self.component_path = "/dashboard"
      end
      page = Class.new(Weft::Page) { def self.name = "DashboardPage" } # -> /dashboard
      registry.register(comp)
      registry.register_page(page)

      expect { registry.lookup("/dashboard") }.to raise_error(
        Weft::InvalidDefinition, %r{Route collision on "/dashboard".*Dashboard}m
      )
    end

    it "raises when a component path collides with another component's stream endpoint" do
      # base /_components/live, stream tail /_components/live/_stream. Name
      # derivation can't produce a leading-underscore segment, so reaching a
      # stream tail requires an explicit component_path (that's the point of the
      # "_stream" default — it fences the tails off from derived component paths).
      streamer = Class.new(Weft::Component) do
        def self.name = "Live"
        pushes every: 5
      end
      clasher = Class.new(Weft::Component) do
        def self.name = "Clasher"
        param :x
        self.component_path = "/_components/live/_stream"
      end
      registry.register(streamer)
      registry.register(clasher)

      expect { registry.lookup("/_components/live") }.to raise_error(
        Weft::InvalidDefinition, /Route collision.*stream/mi
      )
    end

    it "does not raise for distinct routable components and pages" do
      registry.register(component_class)
      registry.register(namespaced_class)
      page = Class.new(Weft::Page) { def self.name = "HomePage" }
      registry.register_page(page)

      expect { registry.lookup("/_components/stat_card") }.not_to raise_error
      expect { registry.match_page("/home") }.not_to raise_error
    end
  end

  describe "dependent-receives lint" do
    before { allow(Weft.logger).to receive(:warn) }

    it "warns for a routable component whose hand-off has no wire dual" do
      klass = Class.new(Weft::Component) do
        def self.name = "LintedPanel"
        param :status
        receives :order
      end
      registry.register(klass)

      registry.lookup("/_components/linted_panel")

      expect(Weft.logger).to have_received(:warn).with(/LintedPanel.*:order.*dependent!/m)
    end

    it "stays quiet for a defaulted hand-off — declaring a default opts into standalone degradation" do
      klass = Class.new(Weft::Component) do
        def self.name = "SoftLintPanel"
        param :status
        receives :label, default: nil
      end
      registry.register(klass)

      registry.lookup("/_components/soft_lint_panel")

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays quiet when the hand-off has a wire dual" do
      klass = Class.new(Weft::Component) do
        def self.name = "DualedPanel"
        param :status
        receives :status
      end
      registry.register(klass)

      registry.lookup("/_components/dualed_panel")

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays quiet for a dependent! class" do
      klass = Class.new(Weft::Component) do
        def self.name = "MarkedPanel"
        param :status
        receives :order
        dependent!
      end
      registry.register(klass)

      registry.lookup("/_components/marked_panel")

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays quiet for a component that is not routable to begin with" do
      klass = Class.new(Weft::Component) do
        def self.name = "QuietSlip"
        receives :order
      end
      registry.register(klass)

      registry.lookup("/_components/quiet_slip")

      expect(Weft.logger).not_to have_received(:warn)
    end
  end

  describe "stale (redefined) class handling" do
    it "drops a superseded class so only the live definition routes (no false collision)" do
      stub_const("ReloadPanel", Class.new(Weft::Component) { param :x })
      registry.register(ReloadPanel)
      original = ReloadPanel
      # Simulate a code-reloader redefining the constant: a new class object
      # takes over the name; the old object lingers in the registry.
      stub_const("ReloadPanel", Class.new(Weft::Component) { param :x })
      registry.register(ReloadPanel)

      expect { registry.lookup("/_components/reload_panel") }.not_to raise_error
      expect(registry.lookup("/_components/reload_panel")).to eq(ReloadPanel)
      expect(registry.components).not_to include(original)
    end
  end

  describe "#clear" do
    it "empties components and pages" do
      registry.register(component_class)
      registry.register_page(Class.new(Weft::Page) { def self.name = "HomePage" })

      registry.clear

      expect(registry.components).to be_empty
      expect(registry.pages).to be_empty
    end
  end

  describe "route well-formedness (tier-B)" do
    it "raises for a routable component whose custom path is not a valid route" do
      bad = Class.new(Weft::Component) do
        def self.name = "Bad"
        param :x
        self.component_path = "relative-no-slash"
      end
      registry.register(bad)

      expect { registry.lookup("/anything") }.to raise_error(
        Weft::InvalidDefinition, /not a valid route/
      )
    end

    it "allows an explicit \"/\" homepage page" do
      home = Class.new(Weft::Page) do
        def self.name = "HomePage"
        self.page_path = "/"
      end
      registry.register_page(home)

      expect { registry.match_page("/") }.not_to raise_error
      expect(registry.match_page("/")).to eq([home, {}])
    end
  end

  describe "page matching" do
    let(:page_class) do
      Class.new(Weft::Page) do
        def self.name = "OrderPage"
        self.page_path = "/orders/:order_id"
        param :order_id
      end
    end

    let(:dashboard_class) do
      Class.new(Weft::Page) do
        def self.name = "DashPage"
        self.page_path = "/dashboard"
      end
    end

    before do
      registry.register_page(page_class)
      registry.register_page(dashboard_class)
    end

    it "matches a parameterized path and extracts params" do
      result = registry.match_page("/orders/abc-123")

      expect(result).not_to be_nil
      klass, params = result
      expect(klass).to eq(page_class)
      expect(params).to eq(order_id: "abc-123")
    end

    it "matches a non-parameterized path" do
      result = registry.match_page("/dashboard")

      expect(result).not_to be_nil
      klass, params = result
      expect(klass).to eq(dashboard_class)
      expect(params).to eq({})
    end

    it "returns nil for unmatched paths" do
      expect(registry.match_page("/unknown")).to be_nil
    end

    it "does not match partial paths" do
      expect(registry.match_page("/orders")).to be_nil
    end

    it "auto-registers pages via inherited hook" do
      page = Class.new(Weft::Page) do
        def self.name = "AutoRegPage"
        self.page_path = "/auto"
      end

      expect(Weft.registry.pages).to include(page)
    end
  end

  describe "#any_sse_components?" do
    let(:plain_component) do
      Class.new(Weft::Component) { def self.name = "PlainCard" }
    end

    let(:sse_component) do
      Class.new(Weft::Component) do
        def self.name = "LiveCard"
        pushes every: 5
      end
    end

    it "returns false for an empty registry" do
      expect(registry.any_sse_components?).to be(false)
    end

    it "returns false when no registered component declares pushes" do
      registry.register(plain_component)
      expect(registry.any_sse_components?).to be(false)
    end

    it "returns true when a registered component declares pushes" do
      registry.register(sse_component)
      expect(registry.any_sse_components?).to be(true)
    end

    it "recomputes while still false, picking up a pushing component registered later" do
      registry.register(plain_component)
      expect(registry.any_sse_components?).to be(false)

      registry.register(sse_component)
      expect(registry.any_sse_components?).to be(true)
    end

    it "sticks once true, without recomputing after a later registration (one-way memo)" do
      registry.register(sse_component)
      expect(registry.any_sse_components?).to be(true)

      components = registry.instance_variable_get(:@components)
      allow(components).to receive(:any?).and_call_original
      registry.register(plain_component)

      expect(registry.any_sse_components?).to be(true)
      expect(components).not_to have_received(:any?)
    end
  end
end
