# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Component do
  describe "param DSL" do
    it "declares attributes with defaults" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :status, default: "active"
      end

      expect(component_class.params).to eq(status: { default: "active" })
    end

    it "declares attributes without defaults" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :order_id
      end

      expect(component_class.params).to eq(order_id: { default: nil })
    end

    it "accepts an optional type: kwarg" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :page, default: 1, type: :integer
      end

      expect(component_class.params[:page]).to eq(default: 1, type: :integer)
    end

    it "accumulates multiple attributes in declaration order" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :order_id
        param :status, default: "pending"
      end

      expect(component_class.params.keys).to eq(%i[order_id status])
    end

    it "inherits parent attributes in subclasses" do
      parent = Class.new(described_class) do
        def self.name = "BaseCard"
        param :status
      end
      child = Class.new(parent) do
        def self.name = "SpecialCard"
        param :priority, default: "low"
      end

      expect(child.params.keys).to eq(%i[status priority])
      # Parent is unaffected
      expect(parent.params.keys).to eq(%i[status])
    end

    it "an overriding redeclaration takes effect end to end" do
      parent = Class.new(described_class) do
        def self.name = "PagedBase"
        param :per_page, default: 25
      end
      child = Class.new(parent) do
        def self.name = "WidePager"
        param :per_page, default: 100
      end
      component = Weft::Context.new { insert_tag(child) }.children.first

      expect(component.params.per_page).to eq(100)
      expect(component.weft_url).to eq("/_components/wide_pager?per_page=100")
    end
  end

  describe "receives DSL" do
    it "does not make a component routable" do
      component_class = Class.new(described_class) do
        def self.name = "HandOffOnly"
        receives :order
      end

      expect(component_class.routable?).to be(false)
    end
  end

  describe "derives DSL" do
    it "does not make a component routable" do
      component_class = Class.new(described_class) do
        def self.name = "DeriveOnly"
        derives(:order) { |_p| nil }
      end

      expect(component_class.routable?).to be(false)
    end
  end

  describe "receives behavior" do
    let(:order) { Struct.new(:id, :name).new(42, "Widget crate") }

    let(:receiver_class) do
      Class.new(described_class) do
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
      klass = Class.new(described_class) do
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
      second = Class.new(described_class) do
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
      klass = Class.new(described_class) do
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
        Class.new(described_class) do
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
      klass = Class.new(described_class) do
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
      klass = Class.new(described_class) do
        def self.name = "UntouchedDerives"
        param :status
      end
      klass.derives(:expensive) { |_p| runs += 1 }

      Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) { insert_tag(klass) }.to_s

      expect(runs).to eq(0)
    end

    it "memoizes per render: two reads, one derivation" do
      runs = 0
      klass = Class.new(described_class) do
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
      klass = Class.new(described_class) do
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
      klass = Class.new(described_class) do
        def self.name = "QuietlyDerivingPanel"
        param :status
        refreshes every: 5
      end
      klass.derives(:order) { |_p| runs += 1 }
      component = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) do
        insert_tag(klass)
      end.children.first

      expect(component.get_attribute("hx-get")).to eq("/_components/quietly_deriving_panel?status=hot")
      expect(component.weft_id).to eq("quietly-deriving-panel-hot")
      expect(runs).to eq(0)
    end

    it "forces a thunk occupying a WIRE-schema key at serialization (the refresh contract wins)" do
      klass = Class.new(described_class) do
        def self.name = "DualWireDerives"
        param :order_id
        derives(:order_id) { |_p| 99 }
      end
      component = Weft::Context.new { insert_tag(klass) }.children.first

      expect(component.weft_url).to eq("/_components/dual_wire_derives?order_id=99")
    end

    it "a declared-but-never-read failing derivation never raises" do
      klass = Class.new(described_class) do
        def self.name = "SafelyBrokenDerives"
        derives(:doomed) { |_p| raise "boom" }
      end

      expect { Weft::Context.new { insert_tag(klass) }.to_s }.not_to raise_error
    end

    it "defines fills a superclass's expectations through the bag" do
      base = Class.new(described_class) do
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
      parent_class = Class.new(described_class) { def self.name = "DefiningParent" }
      parent_class.defines(label: "upstream")
      child_class = Class.new(described_class) { def self.name = "DefiningChild" }
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
      Class.new(described_class) do
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
      klass = Class.new(described_class) do
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
      parent_class = Class.new(described_class) { def self.name = "UpstreamDeriver" }
      parent_class.derives(:order) { |_p| "upstream" }
      child_class = Class.new(described_class) { def self.name = "ShadowedDeriver" }
      child_class.derives(:order) { |_p| "local" }

      embed_under(parent_class, child_class)
      embed_under(parent_class, child_class)

      expect(Weft.logger).to have_received(:warn).with(/ShadowedDeriver.*:order/m).once
    end

    it "warns even after the ancestor forced its value (provenance survives forcing)" do
      parent_class = Class.new(described_class) { def self.name = "ForcedUpstream" }
      parent_class.derives(:order) { |_p| "upstream" }
      child_class = Class.new(described_class) { def self.name = "ForcedShadowed" }
      child_class.derives(:order) { |_p| "local" }

      embed_under(parent_class, child_class, force: true)

      expect(Weft.logger).to have_received(:warn).with(/ForcedShadowed.*:order/m)
    end

    it "stays silent for a shared derivation (same proc via a mixin)" do
      shared = proc { |_p| "current-user" }
      parent_class = Class.new(described_class) { def self.name = "SharingParent" }
      parent_class.derives(:current_user, &shared)
      child_class = Class.new(described_class) { def self.name = "SharingChild" }
      child_class.derives(:current_user, &shared)

      embed_under(parent_class, child_class)

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "stays silent when the inherited value came through another door (no derivation to diverge from)" do
      parent_class = Class.new(described_class) do
        def self.name = "HandedUpstream"
        receives :order
      end
      child_class = Class.new(described_class) { def self.name = "QuietDeriver" }
      child_class.derives(:order) { |_p| "local" }
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      Weft::Context.new { insert_tag(parent_class, order: "handed") }.to_s

      expect(Weft.logger).not_to have_received(:warn)
    end

    it "warns when a class-ancestry override is shadowed by a tree ancestor of the parent class" do
      parent_class = Class.new(described_class) { def self.name = "BaseDeriver" }
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
      parent_class = Class.new(described_class) { def self.name = "UnshadowedBase" }
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
      child_class = Class.new(described_class) { def self.name = "RidingChild" }
      parent_class = Class.new(described_class) { def self.name = "ForcingParent" }
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
      parent_class = Class.new(described_class) { def self.name = "LazyParent" }
      parent_class.derives(:expensive) { |_p| runs += 1 }
      child_class = Class.new(described_class) { def self.name = "IdleChild" }

      embed_pair(parent_class, child_class).to_s

      expect(runs).to eq(0)
    end

    it "re-derives per branch when siblings force an inherited thunk independently" do
      runs = 0
      parent_class = Class.new(described_class) { def self.name = "SharedThunkParent" }
      parent_class.derives(:order) { |_p| runs += 1 }
      # params resolve at construction, so a reader needn't even call super
      reader = proc { |_attributes = {}| params.order }
      first_child = Class.new(described_class) { def self.name = "GreedySiblingA" }
      first_child.define_method(:build, &reader)
      second_child = Class.new(described_class) { def self.name = "GreedySiblingB" }
      second_child.define_method(:build, &reader)

      embed_pair(parent_class, first_child, second_child).to_s

      expect(runs).to eq(2)
    end

    it "lets an inherited unforced thunk beat the child's own default (it occupies the key)" do
      parent_class = Class.new(described_class) { def self.name = "ThunkedParent" }
      parent_class.derives(:status) { |_p| "derived" }
      child_class = Class.new(described_class) do
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
      parent_class = Class.new(described_class) do
        def self.name = "AxisParent"
        receives :order
      end
      child_class = Class.new(described_class) { def self.name = "AxisChild" }

      child = embed(parent_class, child_class, parent_kwargs: { order: order })

      expect(child.params.order).to be(order)
    end

    it "does not let a component see beside itself" do
      first = Class.new(described_class) do
        def self.name = "LoudSibling"
        receives :order
      end
      second = Class.new(described_class) { def self.name = "QuietSibling" }

      ctx = Weft::Context.new do
        insert_tag(first, order: Struct.new(:id).new(1))
        insert_tag(second)
      end

      expect(ctx.children[1].params.key?(:order)).to be(false)
    end

    it "lets an inherited value beat the child's own default (level 3 over 5)" do
      parent_class = Class.new(described_class) do
        def self.name = "CalmParent"
        receives :status
      end
      child_class = Class.new(described_class) do
        def self.name = "DefaultedChild"
        param :status, default: "all"
      end

      child = embed(parent_class, child_class, parent_kwargs: { status: "calm" })

      expect(child.params.status).to eq("calm")
    end

    it "lets the child's own wire value beat an inherited one (level 2 over 3)" do
      parent_class = Class.new(described_class) do
        def self.name = "HandedParent"
        receives :status
      end
      child_class = Class.new(described_class) do
        def self.name = "WiredChild"
        param :status
      end

      child = embed(parent_class, child_class,
                    wire: { "status" => "hot" }, parent_kwargs: { status: "calm" })

      expect(child.params.status).to eq("hot")
    end

    it "never lets an ancestor's nil shadow the child's default" do
      parent_class = Class.new(described_class) do
        def self.name = "EmptyHandedParent"
        param :label
      end
      child_class = Class.new(described_class) do
        def self.name = "SelfSufficientChild"
        param :label, default: "fallback"
      end

      child = embed(parent_class, child_class)

      expect(child.params.label).to eq("fallback")
    end

    it "satisfies a required hand-off from the ancestor bag — bare embeds stay bare" do
      parent_class = Class.new(described_class) do
        def self.name = "ProvidingParent"
        receives :order
      end
      child_class = Class.new(described_class) do
        def self.name = "DependentChild"
        receives :order
      end

      child = embed(parent_class, child_class, parent_kwargs: { order: order })

      expect(child.params.order).to be(order)
    end

    it "branches the nearest Weft ancestor across intervening HTML elements" do
      child_class = Class.new(described_class) { def self.name = "NestedChild" }
      parent_class = Class.new(described_class) do
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
      child_class = Class.new(described_class) { def self.name = "PageChild" }
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

  describe "receives in a plain Arbre::Context" do
    let(:order) { Struct.new(:id, :name).new(11, "Drum of cable") }

    it "extracts handed kwargs at build-top — params, never chrome" do
      klass = Class.new(described_class) do
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
      klass = Class.new(described_class) do
        def self.name = "PlainStrictSlip"
        receives :order
      end

      expect { Arbre::Context.new { insert_tag(klass) } }.
        to raise_error(Weft::NotReceived, /PlainStrictSlip.*:order/)
    end

    it "applies declared defaults when nothing is handed" do
      klass = Class.new(described_class) do
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
      klass = Class.new(described_class) do
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

  describe "serialization projection" do
    let(:order) { Struct.new(:id, :name).new(9, "Crate") }

    it "serializes own wire params only into weft_url — hand-offs stay server-side" do
      klass = Class.new(described_class) do
        def self.name = "ManifestCard"
        param :status
        receives :order
      end
      handed = order
      component = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) do
        insert_tag(klass, order: handed)
      end.children.first

      expect(component.weft_url).to eq("/_components/manifest_card?status=hot")
    end

    it "keeps inherited values out of weft_url" do
      parent_class = Class.new(described_class) do
        def self.name = "UrlParent"
        param :region, default: "west"
      end
      child_class = Class.new(described_class) do
        def self.name = "UrlChild"
        param :status, default: "open"
      end
      parent_class.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child_class)
      end

      ctx = Weft::Context.new { insert_tag(parent_class) }
      child = ctx.children.first.children.find { |el| el.is_a?(child_class) }

      # region is readable (inheritance axis) but not part of the refresh contract
      expect(child.weft_url).to eq("/_components/url_child?status=open")
    end

    it "serializes a handed value through its wire dual — the refresh keeps it" do
      klass = Class.new(described_class) do
        def self.name = "DualCard"
        param :status
        receives :status
      end
      component = Weft::Context.new { insert_tag(klass, status: "fresh") }.children.first

      expect(component.weft_url).to eq("/_components/dual_card?status=fresh")
    end

    it "derives weft_id from own wire params only, never a hand-off" do
      klass = Class.new(described_class) do
        def self.name = "SlipCard"
        receives :order
      end
      handed = order
      component = Weft::Context.new { insert_tag(klass, order: handed) }.children.first

      expect(component.weft_id).to eq("slip-card")
    end

    it "keeps hand-offs out of the SSE stream URL" do
      klass = Class.new(described_class) do
        def self.name = "TickerCard"
        param :symbol
        receives :feed
        pushes every: 5
      end
      component = Weft::Context.new({}, nil, wire_params: { "symbol" => "WEFT" }) do
        insert_tag(klass, feed: Object.new)
      end.children.first

      expect(component.get_attribute("sse-connect")).to eq("/_components/ticker_card/_stream?symbol=WEFT")
    end
  end

  describe "weft_id" do
    it "derives ID from class name and primary param value" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
        param :status
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) do
        insert_tag(component_class)
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
        param :order_id
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "order_id" => 42 }) do
        insert_tag(component_class)
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
        param :id
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
        param :status
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

    it "is not routable when bare (no params, verbs, or declarations)" do
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
        param :id
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
          param :id
          abstract!
        end

        expect(component_class).not_to be_routable
      end

      it "abstract! does not percolate — concrete subclass is routable again" do
        parent = Class.new(described_class) do
          def self.name = "AbstractParent"
          param :id
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

      it "dependent! makes a routable class non-routable, like abstract!" do
        component_class = Class.new(described_class) do
          def self.name = "LeafComponent"
          param :highlight
          receives :order
          dependent!
        end

        expect(component_class).not_to be_routable
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
        param :order_id
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
        param :status, default: "all"
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
        param :status, default: "all"
        refreshes every: 5.seconds
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 5s"')
    end

    it "renders sub-second every: values in milliseconds" do
      component_class = Class.new(described_class) do
        def self.name = "FastCard"
        param :status, default: "all"
        refreshes every: 0.6
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 600ms"')
    end

    it "renders fractional multi-second every: values in milliseconds" do
      component_class = Class.new(described_class) do
        def self.name = "FractionalCard"
        param :status, default: "all"
        refreshes every: 2.5
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 2500ms"')
    end

    it "warns and rounds every: values below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(described_class) do
        def self.name = "TooFastCard"
        param :status, default: "all"
        refreshes every: 0.0000001
      end

      html = component_class.render(status: "shipped")

      expect(html).to include('hx-trigger="every 1ms"')
      expect(Weft.logger).to have_received(:warn).with(/below the 1ms floor/)
    end

    it "generates event-driven htmx attributes with on:" do
      component_class = Class.new(described_class) do
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
      component_class = Class.new(described_class) do
        def self.name = "CombinedCard"
        param :id
        refreshes every: 30
        refreshes on: "item-updated"
      end

      html = component_class.render(id: "1")

      expect(html).to include('hx-trigger="every 30s, item-updated from:body"')
    end

    it "does not set refresh attributes when no refreshes declared" do
      component_class = Class.new(described_class) do
        def self.name = "StaticCard"
        param :label
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
        param :id
        refreshes on: "updated"
      end

      html = child.render(id: "1")

      expect(html).to include("every 15s")
      expect(html).to include("updated from:body")
    end

    it "omits nil params from the refresh URL" do
      component_class = Class.new(described_class) do
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
    it "generates SSE htmx attributes with every:" do
      component_class = Class.new(described_class) do
        def self.name = "PushCard"
        param :order_id

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
        param :order_id
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
        param :label
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
      component_class = Class.new(described_class) do
        def self.name = "FastTicker"
        param :label
        pushes every: 0.5
      end

      expect(component_class.push_config).to eq(every: 0.5)
    end

    it "warns and rounds a pushes interval below one millisecond up to 1ms" do
      allow(Weft.logger).to receive(:warn)

      component_class = Class.new(described_class) do
        def self.name = "TooFastTicker"
        param :label
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
        param :order_id
        pushes every: 5
      end

      html = component_class.render(order_id: "99")

      expect(html).to include('sse-swap="oms-shipment-card-99"')
    end

    it "omits nil params from the stream URL" do
      component_class = Class.new(described_class) do
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
      component_class.includes(included) { |params| { id: params[:order_id] } }

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
        param :item_id
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
    it "returns the component path with current params" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped", "page" => 2 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?status=shipped&page=2")
    end

    it "overrides specific params" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped", "page" => 2 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url(page: 3)).to eq("/_components/panel?status=shipped&page=3")
    end

    it "omits nil values from the URL" do
      component_class = Class.new(described_class) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "page" => 1 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?page=1")
    end
  end

  describe ".render" do
    it "renders a component to an HTML string outside any DSL context" do
      component_class = Class.new(described_class) do
        def self.name = "Renderable"
        param :status

        def build(attributes = {})
          super
          div { text_node "status=#{params.status}" }
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
    it "resolves declared params from the context's wire params" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :status
        param :count, default: 0

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}, count=#{params[:count]}" }
        end
      end

      html = Weft::Context.new({}, nil, wire_params: { "status" => "active", "count" => "5" }) do
        insert_tag(component_class)
      end.to_s

      expect(html).to include("status=active, count=5")
    end

    it "applies defaults for params missing from the wire" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}" }
        end
      end

      html = Weft::Context.new({}, nil) { insert_tag(component_class) }.to_s

      expect(html).to include("status=pending")
    end

    it "resolves wire params at any tree depth, not just the root" do
      child = Class.new(described_class) do
        def self.name = "DepthChild"
        param :status

        def build(attributes = {})
          super
          text_node "child sees #{params.status}"
        end
      end
      parent = Class.new(described_class) { def self.name = "DepthParent" }
      parent.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child)
      end

      html = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) { insert_tag(parent) }.to_s

      expect(html).to include("child sees shipped")
    end

    it "makes params readable before super in a build body" do
      component_class = Class.new(described_class) do
        def self.name = "EarlyReader"
        param :status

        def build(attributes = {})
          attributes[:class] = "pre-#{params.status}"
          super
        end
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) { insert_tag(component_class) }

      expect(ctx.children.first.class_list).to include("pre-hot")
    end

    it "falls back to defaults in a plain Arbre::Context (no wire source)" do
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}" }
        end
      end

      html = Arbre::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("status=pending")
    end

    it "routes a param-named builder kwarg to chrome, not the bag" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(described_class) do
        def self.name = "TestCard"
        param :status, default: "pending"
      end

      ctx = Weft::Context.new({}, nil) { insert_tag(component_class, status: "shipped") }
      component = ctx.children.first

      expect(component.params.status).to eq("pending")
      expect(component.get_attribute(:status)).to eq("shipped")
    end

    it "warns once per class and key when a param-named kwarg arrives" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(described_class) do
        def self.name = "CollideCard"
        param :title
      end

      Weft::Context.new({}, nil) do
        insert_tag(component_class, title: "a")
        insert_tag(component_class, title: "b")
      end.to_s

      expect(Weft.logger).to have_received(:warn).once.with(/title/)
    end

    it "sets the DOM id from weft_id" do
      component_class = Class.new(described_class) do
        def self.name = "StatCard"
        param :status
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.id).to eq("stat-card-shipped")
    end

    it "does not mutate the caller's attributes hash" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(described_class) do
        def self.name = "NonMutating"
        param :status
      end

      shared = { status: "shipped", class: "big" }
      Weft::Context.new({}, nil) { insert_tag(component_class, **shared) }.to_s

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
      handler = ->(_params, _error) { { message: "oops" } }
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
