# frozen_string_literal: true

require "arbre"

# The source stack a component's params resolve through: staged hand-off >
# own wire value > inherited bag value > declared default, with overlays
# speaking as the wire. Exercised through Weft::Component, which is what
# assembles a bag in practice.
RSpec.describe Weft::Params::Assembly do
  describe "receives behavior" do
    let(:order) { Struct.new(:id, :name).new(42, "Widget crate") }

    let(:receiver_class) do
      Class.new(Weft::Component) do
        def self.name = "OrderSlip"
        receives :order

        def build(attributes = {})
          super
          span params.order.name
        end
      end
    end

    it "lands a handed kwarg in params, never in HTML chrome" do
      klass = receiver_class
      handed = order
      ctx = Weft::Context.new { insert_tag(klass, order: handed) }
      component = ctx.children.first

      expect(component.params.order).to be(handed)
      expect(component.attributes).not_to have_key(:order)
      expect(ctx.to_s).to include("Widget crate")
    end

    it "makes handed values readable before super in a build body" do
      klass = Class.new(Weft::Component) do
        def self.name = "EagerReceiver"
        receives :label

        def build(attributes = {})
          attributes[:class] = "for-#{params.label}"
          super
        end
      end

      ctx = Weft::Context.new { insert_tag(klass, label: "totals") }

      expect(ctx.children.first.class_list).to include("for-totals")
    end

    it "does not leak one sibling's hand-off to the next" do
      first = receiver_class
      second = Class.new(Weft::Component) do
        def self.name = "BareSlip"
        receives :order, default: nil
      end
      handed = order

      ctx = Weft::Context.new do
        insert_tag(first, order: handed)
        insert_tag(second)
      end

      expect(ctx.children[1].params.order).to be_nil
    end

    it "raises NotReceived at the call site when a required hand-off is missing" do
      klass = receiver_class

      expect { Weft::Context.new { insert_tag(klass) } }.
        to raise_error(Weft::NotReceived, /OrderSlip.*:order/)
    end

    it "softens absence to the declared default, even an explicit nil" do
      klass = Class.new(Weft::Component) do
        def self.name = "SoftSlip"
        receives :page_num, default: 1
        receives :accent, default: nil
      end
      component = Weft::Context.new { insert_tag(klass) }.children.first

      expect(component.params.page_num).to eq(1)
      expect(component.params.accent).to be_nil
    end

    context "with a param dual on the same key" do
      let(:dual_class) do
        Class.new(Weft::Component) do
          def self.name = "StatusChip"
          param :status
          receives :status
        end
      end

      it "prefers the handed value over the wire" do
        klass = dual_class
        component = Weft::Context.new({}, nil, wire_params: { "status" => "stale" }) do
          insert_tag(klass, status: "fresh")
        end.children.first

        expect(component.params.status).to eq("fresh")
      end

      it "falls back to the wire when nothing is handed" do
        klass = dual_class
        component = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) do
          insert_tag(klass)
        end.children.first

        expect(component.params.status).to eq("shipped")
      end

      it "resolves to nil without raising when no source supplies the key" do
        klass = dual_class
        component = Weft::Context.new { insert_tag(klass) }.children.first

        expect(component.params.status).to be_nil
      end
    end

    it "cannot be satisfied through render's pseudo-wire kwargs" do
      # render kwargs are a query string in disguise; a hand-off is a
      # server-side value that can't ride the wire. Build under Weft::Context
      # with call-site kwargs to test receiving components.
      expect { receiver_class.render(order: order) }.
        to raise_error(Weft::NotReceived)
    end
  end

  describe "derives behavior" do
    it "derives from other params at first read, in build, before or after super" do
      klass = Class.new(Weft::Component) do
        def self.name = "DerivingCard"
        param :order_id
        derives(:order) { |p| "order-#{p.order_id}" }

        def build(attributes = {})
          attributes[:class] = "pre-#{params.order}"
          super
          span params.order
        end
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "order_id" => 7 }) { insert_tag(klass) }

      expect(ctx.children.first.class_list).to include("pre-order-7")
      expect(ctx.to_s).to include("order-7")
    end

    it "never runs an unread derivation" do
      runs = 0
      klass = Class.new(Weft::Component) do
        def self.name = "UntouchedDerives"
        param :status
      end
      klass.derives(:expensive) { |_p| runs += 1 }

      Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) { insert_tag(klass) }.to_s

      expect(runs).to eq(0)
    end

    it "memoizes per render: two reads, one derivation" do
      runs = 0
      klass = Class.new(Weft::Component) do
        def self.name = "MemoizedDerives"
      end
      klass.derives(:order) do |_p|
        runs += 1
        "the-order"
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        span params.order
        span params.order
      end

      Weft::Context.new { insert_tag(klass) }.to_s

      expect(runs).to eq(1)
    end

    it "works in a plain Arbre::Context (registration is receiver-side)" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainDerives"
        derives(:greeting) { |_p| "hello" }

        def build(attributes = {})
          super
          span params.greeting
        end
      end

      expect(Arbre::Context.new { insert_tag(klass) }.to_s).to include("hello")
    end

    it "does not force derivations for serialization surfaces" do
      runs = 0
      klass = Class.new(Weft::Component) do
        def self.name = "QuietlyDerivingPanel"
        param :status
        identifies_by :status
        refreshes every: 5
      end
      klass.derives(:order) { |_p| runs += 1 }
      component = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) do
        insert_tag(klass)
      end.children.first

      expect(component.get_attribute("hx-get")).to eq("/_components/quietly_deriving_panel?status=hot")
      expect(component.weft_dom_id).to eq("quietly-deriving-panel-hot")
      expect(runs).to eq(0)
    end

    it "forces a thunk occupying a WIRE-schema key at serialization (the refresh contract wins)" do
      klass = Class.new(Weft::Component) do
        def self.name = "DualWireDerives"
        param :order_id
        derives(:order_id) { |_p| 99 }
      end
      component = Weft::Context.new { insert_tag(klass) }.children.first

      expect(component.weft_url).to eq("/_components/dual_wire_derives?order_id=99")
    end

    it "a declared-but-never-read failing derivation never raises" do
      klass = Class.new(Weft::Component) do
        def self.name = "SafelyBrokenDerives"
        derives(:doomed) { |_p| raise "boom" }
      end

      expect { Weft::Context.new { insert_tag(klass) }.to_s }.not_to raise_error
    end

    it "defines fills a superclass's expectations through the bag" do
      base = Class.new(Weft::Component) do
        def self.name = "FaceCard"
        receives :label, default: nil

        def build(attributes = {})
          super
          span params.label.to_s
        end
      end
      child = Class.new(base) do
        def self.name = "StaticFaceCard"
        defines label: "Drivers"
      end

      expect(Weft::Context.new { insert_tag(child) }.to_s).to include("Drivers")
    end

    it "two divergent defines of one key trip the divergence warning like any derivations" do
      allow(Weft.logger).to receive(:warn)
      parent_class = Class.new(Weft::Component) { def self.name = "DefiningParent" }
      parent_class.defines(label: "upstream")
      child_class = Class.new(Weft::Component) { def self.name = "DefiningChild" }
      child_class.defines(label: "local")
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      Weft::Context.new { insert_tag(parent_class) }.to_s

      expect(Weft.logger).to have_received(:warn).with(/DefiningChild.*:label/m)
    end
  end

  describe "dual-pipeline keys (derives + receives parity)" do
    let(:runs) { [] }
    let(:dual_class) do
      collector = runs
      Class.new(Weft::Component) do
        def self.name = "ParityCard"
        receives :order
        derives(:order) do |_p|
          collector << :derived
          "self-fetched"
        end
      end
    end

    it "prefers a handed value; the derivation never runs" do
      klass = dual_class
      component = Weft::Context.new { insert_tag(klass, order: "handed") }.children.first

      expect(component.params.order).to eq("handed")
      expect(runs).to be_empty
    end

    it "self-derives when nothing is handed — the dual softens the receives, no raise" do
      klass = dual_class
      component = Weft::Context.new { insert_tag(klass) }.children.first

      expect(component.params.order).to eq("self-fetched")
    end

    it "on a param+derives key, the wire wins when present and the derivation covers absence" do
      klass = Class.new(Weft::Component) do
        def self.name = "WireOrDeriveCard"
        param :status
        derives(:status) { |_p| "derived" }
      end

      wired = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) do
        insert_tag(klass)
      end.children.first
      bare = Weft::Context.new { insert_tag(klass) }.children.first

      expect(wired.params.status).to eq("hot")
      expect(bare.params.status).to eq("derived")
    end
  end

  describe "divergent derivation warning" do
    before { allow(Weft.logger).to receive(:warn) }

    def embed_under(parent_class, child_class, force: false)
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        params.order if force
        insert_tag(child_class)
      end
      Weft::Context.new { insert_tag(parent_class) }.to_s
    end

    it "warns once when an inherited derivation shadows the child's own, divergent one" do
      parent_class = Class.new(Weft::Component) { def self.name = "UpstreamDeriver" }
      parent_class.derives(:order) { |_p| "upstream" }
      child_class = Class.new(Weft::Component) { def self.name = "ShadowedDeriver" }
      child_class.derives(:order) { |_p| "local" }

      embed_under(parent_class, child_class)
      embed_under(parent_class, child_class)

      expect(Weft.logger).to have_received(:warn).with(/ShadowedDeriver.*:order/m).once
    end

    it "warns even after the ancestor forced its value (provenance survives forcing)" do
      parent_class = Class.new(Weft::Component) { def self.name = "ForcedUpstream" }
      parent_class.derives(:order) { |_p| "upstream" }
      child_class = Class.new(Weft::Component) { def self.name = "ForcedShadowed" }
      child_class.derives(:order) { |_p| "local" }

      embed_under(parent_class, child_class, force: true)

      expect(Weft.logger).to have_received(:warn).with(/ForcedShadowed.*:order/m)
    end

    it "still warns about a divergent inherited derivation when an overlay took the key" do
      parent_class = Class.new(Weft::Component) { def self.name = "OverlaidUpstream" }
      parent_class.derives(:order) { |_p| "upstream" }
      child_class = Class.new(Weft::Component) { def self.name = "OverlaidShadowed" }
      child_class.derives(:order) { |_p| "local" }
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      Weft::Context.new({}, nil, overlays: { order: "from-a-verb-block" }) { insert_tag(parent_class) }.to_s

      expect(Weft.logger).to have_received(:warn).with(/OverlaidShadowed.*:order.*shadows/m)
    end

    it "warns when a verb block's overlay outranks this class's own derivation" do
      klass = Class.new(Weft::Component) { def self.name = "OverruledDeriver" }
      klass.derives(:label) { |_p| "derived" }

      Weft::Context.new({}, nil, overlays: { label: "from-a-verb-block" }) { insert_tag(klass) }.to_s

      expect(Weft.logger).to have_received(:warn).with(/OverruledDeriver.*:label.*outranks/m)
    end

    it "stays silent when an overlay clears a key rather than supplying one" do
      klass = Class.new(Weft::Component) { def self.name = "ClearedDeriver" }
      klass.derives(:label) { |_p| "derived" }

      Weft::Context.new({}, nil, overlays: { label: nil }) { insert_tag(klass) }.to_s

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays silent for a shared derivation (same proc via a mixin)" do
      shared = proc { |_p| "current-user" }
      parent_class = Class.new(Weft::Component) { def self.name = "SharingParent" }
      parent_class.derives(:current_user, &shared)
      child_class = Class.new(Weft::Component) { def self.name = "SharingChild" }
      child_class.derives(:current_user, &shared)

      embed_under(parent_class, child_class)

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays silent when the inherited value came through another door (no derivation to diverge from)" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "HandedUpstream"
        receives :order
      end
      child_class = Class.new(Weft::Component) { def self.name = "QuietDeriver" }
      child_class.derives(:order) { |_p| "local" }
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      Weft::Context.new { insert_tag(parent_class, order: "handed") }.to_s

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "warns when a class-ancestry override is shadowed by a tree ancestor of the parent class" do
      parent_class = Class.new(Weft::Component) { def self.name = "BaseDeriver" }
      parent_class.derives(:foo) { |_p| "base" }
      child_class = Class.new(parent_class) { def self.name = "OverridingDeriver" }
      child_class.derives(:foo) { |_p| "overridden" }
      # only the parent inserts — the child inherits this build and must not self-insert
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class) if instance_of?(parent_class)
      end

      Weft::Context.new { insert_tag(parent_class) }.to_s

      expect(Weft.logger).to have_received(:warn).with(/OverridingDeriver.*:foo/m)
    end

    it "stays silent for a redeclaration rendered without tree shadowing" do
      parent_class = Class.new(Weft::Component) { def self.name = "UnshadowedBase" }
      parent_class.derives(:foo) { |_p| "base" }
      child_class = Class.new(parent_class) { def self.name = "UnshadowedOverride" }
      child_class.derives(:foo) { |_p| "overridden" }

      Weft::Context.new { insert_tag(child_class) }.to_s

      expect(Weft.logger).not_to have_received(:warn)
    end
  end

  describe "derives across the inheritance axis (copy-on-branch memo)" do
    def embed_pair(parent_class, *child_classes)
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        child_classes.each { |c| insert_tag(c) }
      end
      Weft::Context.new { insert_tag(parent_class) }
    end

    it "rides an ancestor-forced value down: one derivation, same object" do
      runs = 0
      child_class = Class.new(Weft::Component) { def self.name = "RidingChild" }
      parent_class = Class.new(Weft::Component) { def self.name = "ForcingParent" }
      parent_class.derives(:order) { |_p| Object.new.tap { runs += 1 } }
      # force before the child branches; params need no super (construction-resolved)
      parent_class.define_method(:build) do |_attributes = {}|
        params.order
        insert_tag(child_class)
      end

      ctx = Weft::Context.new { insert_tag(parent_class) }
      parent = ctx.children.first
      child = parent.children.find { |el| el.is_a?(child_class) }

      expect(child.params.order).to be(parent.params.order)
      expect(runs).to eq(1)
    end

    it "does not force an unread ancestor thunk just by branching" do
      runs = 0
      parent_class = Class.new(Weft::Component) { def self.name = "LazyParent" }
      parent_class.derives(:expensive) { |_p| runs += 1 }
      child_class = Class.new(Weft::Component) { def self.name = "IdleChild" }

      embed_pair(parent_class, child_class).to_s

      expect(runs).to eq(0)
    end

    it "re-derives per branch when siblings force an inherited thunk independently" do
      runs = 0
      parent_class = Class.new(Weft::Component) { def self.name = "SharedThunkParent" }
      parent_class.derives(:order) { |_p| runs += 1 }
      # params resolve at construction, so a reader needn't even call super
      reader = proc { |_attributes = {}| params.order }
      first_child = Class.new(Weft::Component) { def self.name = "GreedySiblingA" }
      first_child.define_method(:build, &reader)
      second_child = Class.new(Weft::Component) { def self.name = "GreedySiblingB" }
      second_child.define_method(:build, &reader)

      embed_pair(parent_class, first_child, second_child).to_s

      expect(runs).to eq(2)
    end

    it "lets an inherited unforced thunk beat the child's own default (it occupies the key)" do
      parent_class = Class.new(Weft::Component) { def self.name = "ThunkedParent" }
      parent_class.derives(:status) { |_p| "derived" }
      child_class = Class.new(Weft::Component) do
        def self.name = "DefaultingChild"
        param :status, default: "fallback"
      end

      ctx = embed_pair(parent_class, child_class)
      child = ctx.children.first.children.find { |el| el.is_a?(child_class) }

      expect(child.params.status).to eq("derived")
    end
  end

  describe "inheritance axis" do
    let(:order) { Struct.new(:id, :name).new(7, "Pallet of anvils") }

    def embed(parent_class, child_class, wire: {}, parent_kwargs: {})
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end
      ctx = Weft::Context.new({}, nil, wire_params: wire) do
        insert_tag(parent_class, **parent_kwargs)
      end
      ctx.children.first.children.find { |el| el.is_a?(child_class) }
    end

    it "lets a child read an ancestor's bag value it never declared" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "AxisParent"
        receives :order
      end
      child_class = Class.new(Weft::Component) { def self.name = "AxisChild" }

      child = embed(parent_class, child_class, parent_kwargs: { order: order })

      expect(child.params.order).to be(order)
    end

    it "does not let a component see beside itself" do
      first = Class.new(Weft::Component) do
        def self.name = "LoudSibling"
        receives :order
      end
      second = Class.new(Weft::Component) { def self.name = "QuietSibling" }

      ctx = Weft::Context.new do
        insert_tag(first, order: Struct.new(:id).new(1))
        insert_tag(second)
      end

      expect(ctx.children[1].params.key?(:order)).to be(false)
    end

    it "lets an inherited value beat the child's own default (level 3 over 5)" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "CalmParent"
        receives :status
      end
      child_class = Class.new(Weft::Component) do
        def self.name = "DefaultedChild"
        param :status, default: "all"
      end

      child = embed(parent_class, child_class, parent_kwargs: { status: "calm" })

      expect(child.params.status).to eq("calm")
    end

    it "lets the child's own wire value beat an inherited one (level 2 over 3)" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "HandedParent"
        receives :status
      end
      child_class = Class.new(Weft::Component) do
        def self.name = "WiredChild"
        param :status
      end

      child = embed(parent_class, child_class,
                    wire: { "status" => "hot" }, parent_kwargs: { status: "calm" })

      expect(child.params.status).to eq("hot")
    end

    it "never lets an ancestor's nil shadow the child's default" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "EmptyHandedParent"
        param :label
      end
      child_class = Class.new(Weft::Component) do
        def self.name = "SelfSufficientChild"
        param :label, default: "fallback"
      end

      child = embed(parent_class, child_class)

      expect(child.params.label).to eq("fallback")
    end

    it "satisfies a required hand-off from the ancestor bag — bare embeds stay bare" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "ProvidingParent"
        receives :order
      end
      child_class = Class.new(Weft::Component) do
        def self.name = "DependentChild"
        receives :order
      end

      child = embed(parent_class, child_class, parent_kwargs: { order: order })

      expect(child.params.order).to be(order)
    end

    it "branches the nearest Weft ancestor across intervening HTML elements" do
      child_class = Class.new(Weft::Component) { def self.name = "NestedChild" }
      parent_class = Class.new(Weft::Component) do
        def self.name = "WrappingParent"
        receives :order
      end
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        div(class: "wrapper") { insert_tag(child_class) }
      end

      handed = order
      ctx = Weft::Context.new { insert_tag(parent_class, order: handed) }
      child = collect_child(ctx, child_class)

      expect(child.params.order).to be(handed)
    end

    it "branches from a page at the root of the tree" do
      child_class = Class.new(Weft::Component) { def self.name = "PageChild" }
      page_class = Class.new(Weft::Page) do
        def self.name = "AxisPage"
        self.page_path = "/axis/:section"
        param :section
      end
      page_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "section" => "west" }) do
        insert_tag(page_class)
      end
      child = collect_child(ctx, child_class)

      expect(child.params.section).to eq("west")
    end

    def collect_child(ctx, child_class)
      found = nil
      walk = lambda do |el|
        found = el if el.is_a?(child_class)
        el.children.each { |c| walk.call(c) } unless found
      end
      ctx.children.each { |c| walk.call(c) }
      found
    end
  end

  describe "overlay level (request-scoped deltas)" do
    it "speaks as the wire when it holds a key, beating the actual wire value" do
      klass = Class.new(Weft::Component) do
        def self.name = "PagedPanel"
        param :page, type: :integer
      end

      component = Weft::Context.new({}, nil, wire_params: { "page" => "3" },
                                             overlays: { page: 5 }) { insert_tag(klass) }.children.first

      expect(component.params.page).to eq(5)
    end

    it "loses to an explicit hand-off" do
      klass = Class.new(Weft::Component) do
        def self.name = "LabeledCard"
        receives :label
      end

      component = Weft::Context.new({}, nil, overlays: { label: "from-overlay" }) do
        insert_tag(klass, label: "handed")
      end.children.first

      expect(component.params.label).to eq("handed")
    end

    it "pre-empts a derivation with a rich value (the delta already did the work)" do
      klass = Class.new(Weft::Component) do
        def self.name = "OrderPane"
        derives(:order) { |_p| raise "derivation must not run" }
      end
      order = Struct.new(:id).new(42)

      component = Weft::Context.new({}, nil, overlays: { order: order }) { insert_tag(klass) }.children.first

      expect(component.params.order).to be(order)
    end

    it "clears with nil: the wire value is masked and resolution falls below it" do
      klass = Class.new(Weft::Component) do
        def self.name = "StatusCard"
        param :status, type: :string, default: "fresh"
      end

      component = Weft::Context.new({}, nil, wire_params: { "status" => "stale" },
                                             overlays: { status: nil }) { insert_tag(klass) }.children.first

      expect(component.params.status).to eq("fresh")
    end

    it "falls from a nil overlay to a derivation on a dual key" do
      klass = Class.new(Weft::Component) do
        def self.name = "TallyCard"
        param :tally, type: :integer
        derives(:tally) { |_p| 7 }
      end

      component = Weft::Context.new({}, nil, wire_params: { "tally" => "3" },
                                             overlays: { tally: nil }) { insert_tag(klass) }.children.first

      expect(component.params.tally).to eq(7)
    end

    it "reaches nested components at any depth" do
      inner = Class.new(Weft::Component) do
        def self.name = "InnerBadge"
        param :account_id, type: :string
      end

      inner_component = nil
      Weft::Context.new({}, nil, overlays: { account_id: "acct-9" }) do
        div do
          div do
            inner_component = insert_tag(inner)
          end
        end
      end

      expect(inner_component.params.account_id).to eq("acct-9")
    end
  end

  describe "branch bag (root inheritance from the context)" do
    it "lets a root component inherit from a context-provided bag" do
      klass = Class.new(Weft::Component) do
        def self.name = "CompanionCard"
      end
      primary_bag = Weft::Params.new({ order_id: "o-1" })

      component = Weft::Context.new({}, nil, branch_bag: primary_bag) { insert_tag(klass) }.children.first

      expect(component.params[:order_id]).to eq("o-1")
    end

    it "supplies inherited values that pre-empt the root's own derivation" do
      klass = Class.new(Weft::Component) do
        def self.name = "SharedOrderCard"
        derives(:order) { |_p| raise "must inherit, not re-derive" }
      end
      order = Struct.new(:id).new(1)
      primary_bag = Weft::Params.new({ order: order })

      component = Weft::Context.new({}, nil, branch_bag: primary_bag) { insert_tag(klass) }.children.first

      expect(component.params.order).to be(order)
    end

    it "yields to a genuine tree ancestor when one exists" do
      parent = Class.new(Weft::Component) do
        def self.name = "TreeParent"
        param :label, type: :string
      end
      child = Class.new(Weft::Component) do
        def self.name = "TreeChild"
      end

      child_component = nil
      Weft::Context.new({}, nil, wire_params: { "label" => "from-tree" },
                                 branch_bag: Weft::Params.new({ label: "from-branch" })) do
        insert_tag(parent) do
          child_component = insert_tag(child)
        end
      end

      expect(child_component.params[:label]).to eq("from-tree")
    end
  end

  describe "receives in a plain Arbre::Context" do
    let(:order) { Struct.new(:id, :name).new(11, "Drum of cable") }

    it "extracts handed kwargs at build-top — params, never chrome" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainSlip"
        receives :order

        def build(attributes = {})
          super
          span params.order.name
        end
      end
      handed = order
      ctx = Arbre::Context.new { insert_tag(klass, order: handed) }
      component = ctx.children.first

      expect(component.params.order).to be(handed)
      expect(component.attributes).not_to have_key(:order)
      expect(ctx.to_s).to include("Drum of cable")
    end

    it "still raises NotReceived for a required hand-off nobody supplied" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainStrictSlip"
        receives :order
      end

      expect { Arbre::Context.new { insert_tag(klass) } }.
        to raise_error(Weft::NotReceived, /PlainStrictSlip.*:order/)
    end

    it "lands a handed value over a dual derivation without forcing it" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainDualSlip"
        receives :order
        derives(:order) { |_p| raise "standalone-only derivation must not force" }

        def build(attributes = {})
          super
          span params.order.name
        end
      end
      handed = order
      ctx = Arbre::Context.new { insert_tag(klass, order: handed) }

      expect(ctx.to_s).to include("Drum of cable")
    end

    it "leaves unread lazy derivations unforced through the hand-off door" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainLazySlip"
        receives :order
        derives(:audit_trail) { |_p| raise "unread keys must stay lazy" }

        def build(attributes = {})
          super
          span params.order.name
        end
      end
      handed = order
      ctx = Arbre::Context.new { insert_tag(klass, order: handed) }

      expect(ctx.to_s).to include("Drum of cable")
    end

    it "applies declared defaults when nothing is handed" do
      klass = Class.new(Weft::Component) do
        def self.name = "PlainSoftSlip"
        receives :page_num, default: 1
      end
      component = Arbre::Context.new { insert_tag(klass) }.children.first

      expect(component.params.page_num).to eq(1)
    end

    it "resolves a handed value only at build-top: pre-super reads see the fallback tier" do
      # The documented edge: staging happens at interception, which never
      # runs in a plain context. Render receiving components under
      # Weft::Context when a build body must read hand-offs before super.
      reads = {}
      klass = Class.new(Weft::Component) do
        def self.name = "PlainEagerSlip"
        receives :label, default: "unset"
      end
      klass.define_method(:build) do |attributes = {}|
        reads[:before] = params.label
        super(attributes)
        reads[:after] = params.label
      end

      Arbre::Context.new { insert_tag(klass, label: "totals") }

      expect(reads).to eq(before: "unset", after: "totals")
    end
  end
end
