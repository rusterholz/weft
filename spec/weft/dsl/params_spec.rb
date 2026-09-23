# frozen_string_literal: true

require "arbre"
require "bigdecimal"

RSpec.describe Weft::DSL::Params do
  # Test the mixin on a plain class (not Component/Page) to isolate it.
  let(:base_class) do
    Class.new(Arbre::Component) do
      include Weft::DSL::Params

      def self.name = "DslTestBase"
    end
  end

  describe ".param" do
    it "declares attributes with defaults" do
      klass = Class.new(base_class) do
        def self.name = "AttrTest"
        param :status, default: "active"
      end

      expect(klass.params).to eq(status: { default: "active" })
    end

    it "reserves no name for weft — a mint is not a param, so it claims no key" do
      # The mint belongs to the component instance, never to the params bag,
      # which is what leaves the whole namespace to the user.
      klass = Class.new(base_class) do
        def self.name = "MintNamedAttr"
        param :_mint, default: "mine"
      end

      expect(klass.params[:_mint]).to eq(default: "mine")
    end

    it "accepts optional digest: kwarg" do
      klass = Class.new(base_class) do
        def self.name = "DigestedAttr"
        param :label, digest: true
      end

      expect(klass.params[:label]).to eq(default: nil, digest: true)
    end

    it "accepts a digest length in place of true" do
      klass = Class.new(base_class) do
        def self.name = "WideDigestAttr"
        param :label, digest: 12
      end

      expect(klass.params[:label]).to eq(default: nil, digest: 12)
    end

    it "treats digest: false as no digest at all" do
      klass = Class.new(base_class) do
        def self.name = "UndigestedAttr"
        param :label, digest: false
      end

      expect(klass.params[:label]).to eq(default: nil)
    end

    it "composes with type:" do
      klass = Class.new(base_class) do
        def self.name = "TypedDigestAttr"
        param :key, type: :uuid, digest: true
      end

      expect(klass.params[:key]).to eq(default: nil, type: :uuid, digest: true)
    end

    it "rejects a digest length of zero" do
      expect do
        Class.new(base_class) do
          def self.name = "ZeroDigestAttr"
          param :label, digest: 0
        end
      end.to raise_error(Weft::InvalidDefinition, /digest/)
    end

    it "rejects a digest wider than the underlying hash" do
      expect do
        Class.new(base_class) do
          def self.name = "OverwideDigestAttr"
          param :label, digest: 65
        end
      end.to raise_error(Weft::InvalidDefinition, /digest/)
    end

    it "rejects a digest that is neither a flag nor a length" do
      expect do
        Class.new(base_class) do
          def self.name = "BogusDigestAttr"
          param :label, digest: "wide"
        end
      end.to raise_error(Weft::InvalidDefinition, /digest/)
    end

    it "accepts optional type: kwarg" do
      klass = Class.new(base_class) do
        def self.name = "TypedAttr"
        param :page, default: 1, type: :integer
      end

      expect(klass.params[:page]).to eq(default: 1, type: :integer)
    end

    it "accepts every registered type" do
      klass = Class.new(base_class) do
        def self.name = "AllTypesTest"
        Weft::Types.registered.each { |type| param :"a_#{type}", type: type }
      end

      expect(klass.params.values.map { |meta| meta[:type] }).to eq(Weft::Types.registered)
    end

    it "raises InvalidDefinition on an unknown type" do
      expect do
        Class.new(base_class) do
          def self.name = "UnknownTypeTest"
          param :page, type: :number
        end
        # Names the declarable types without pinning their order, which is a
        # property of the registration file rather than of the message — and
        # which a registered type would otherwise break.
      end.to raise_error(Weft::InvalidDefinition) { |error|
        expect(error.message).to match(/:page.*unknown type :number/m)
        expect(error.message).to include(*Weft::Types.registered.map(&:inspect))
      }
    end

    it "raises InvalidDefinition when a non-nil default does not match the declared type" do
      expect do
        Class.new(base_class) do
          def self.name = "MismatchedDefaultTest"
          param :page, default: "1", type: :integer
        end
      end.to raise_error(Weft::InvalidDefinition, /:page.*:integer.*"1".*String/m)
    end

    it "accepts a default that matches the declared type" do
      klass = Class.new(base_class) do
        def self.name = "MatchingDefaultTest"
        param :price, default: BigDecimal("9.99"), type: :decimal
        param :active, default: false, type: :boolean
      end

      expect(klass.params[:price]).to eq(default: BigDecimal("9.99"), type: :decimal)
      expect(klass.params[:active]).to eq(default: false, type: :boolean)
    end

    it "does not accept an Integer default for :float — strict, not numeric-family" do
      expect do
        Class.new(base_class) do
          def self.name = "StrictFloatTest"
          param :rate, default: 1, type: :float
        end
      end.to raise_error(Weft::InvalidDefinition, /:rate.*:float.*Integer/m)
    end

    # One key is one value, so two doors naming different types for it are
    # contradictory assertions rather than a precedence puzzle — the same call
    # `declare_identity!` makes about `identifies_by` and `unique!`.
    describe "a key typed differently by two doors" do
      it "refuses the contradiction rather than picking a winner" do
        expect do
          Class.new(base_class) do
            def self.name = "ContradictedKey"
            param :order_id, type: :integer
            derives(:order_id, type: :uuid) { |_p| 1 }
          end
        end.to raise_error(Weft::InvalidDefinition, /order_id.*:integer.*:uuid/m)
      end

      it "refuses it whichever door declares first" do
        expect do
          Class.new(base_class) do
            def self.name = "ContradictedReverse"
            receives :order_id, type: :uuid
            param :order_id, type: :integer
          end
        end.to raise_error(Weft::InvalidDefinition, /order_id/)
      end

      it "accepts a second door that agrees" do
        klass = Class.new(base_class) do
          def self.name = "AgreeingDoors"
          param :order_id, type: :uuid
          derives(:order_id, type: :uuid) { |_p| 1 }
        end

        expect(klass.declared_type(:order_id)).to eq(:uuid)
      end

      # Not a contradiction: the derivation simply does not restate the type,
      # and the reader finds it through the door that did.
      it "accepts a second door that states nothing" do
        klass = Class.new(base_class) do
          def self.name = "SilentSecondDoor"
          param :order_id, type: :uuid
          derives(:order_id) { |_p| 1 }
        end

        expect(klass.declared_type(:order_id)).to eq(:uuid)
      end

      # A child redeclaring a parent's key is an override, exactly as it is for
      # a derivation block — so the check reads what THIS class body declared,
      # never the inherited merge.
      it "lets a subclass retype a key its parent typed" do
        parent = Class.new(base_class) do
          def self.name = "TypedParent"
          param :order_id, type: :integer
        end
        child = Class.new(parent) do
          def self.name = "RetypingChild"
          param :order_id, type: :uuid
        end

        expect(child.declared_type(:order_id)).to eq(:uuid)
        expect(parent.declared_type(:order_id)).to eq(:integer)
      end
    end

    it "rejects unknown declaration kwargs" do
      expect do
        Class.new(base_class) do
          def self.name = "UnknownKwargTest"
          param :page, typo: :integer
        end
      end.to raise_error(ArgumentError)
    end
  end

  describe ".params inheritance" do
    it "merges parent and child attributes" do
      parent = Class.new(base_class) do
        def self.name = "AttrParent"
        param :status
      end
      child = Class.new(parent) do
        def self.name = "AttrChild"
        param :priority, default: "low"
      end

      expect(child.params.keys).to eq(%i[status priority])
      expect(parent.params.keys).to eq(%i[status])
    end
  end

  describe ".receives" do
    it "declares a required hand-off (no default key in the meta)" do
      klass = Class.new(base_class) do
        def self.name = "ReceivesTest"
        receives :order
      end

      expect(klass.received_params).to eq(order: {})
    end

    it "records a declared default, making the key optional — even an explicit nil" do
      klass = Class.new(base_class) do
        def self.name = "OptionalReceivesTest"
        receives :page_num, default: 1
        receives :accent, default: nil
      end

      expect(klass.received_params).to eq(page_num: { default: 1 }, accent: { default: nil })
    end

    it "accumulates declarations in order, separate from wire params" do
      klass = Class.new(base_class) do
        def self.name = "SeparateStoresTest"
        param :status
        receives :order
        receives :label, default: nil
      end

      expect(klass.received_params.keys).to eq(%i[order label])
      expect(klass.params.keys).to eq(%i[status])
    end

    it "merges parent and child declarations without affecting the parent" do
      parent = Class.new(base_class) do
        def self.name = "ReceivesParent"
        receives :label, default: nil
      end
      child = Class.new(parent) do
        def self.name = "ReceivesChild"
        receives :order
      end

      expect(child.received_params.keys).to eq(%i[label order])
      expect(parent.received_params.keys).to eq(%i[label])
    end

    it "allows a same-key dual with param (both stores carry the key)" do
      klass = Class.new(base_class) do
        def self.name = "DualKeyTest"
        param :status
        receives :status
      end

      expect(klass.params.keys).to eq(%i[status])
      expect(klass.received_params.keys).to eq(%i[status])
    end
  end

  describe "subclass redeclaration (override semantics)" do
    it "replaces the parent's param meta, keeping the parent's declaration position" do
      parent = Class.new(base_class) do
        def self.name = "OverrideParent"
        param :region
        param :per_page, default: 25
      end
      child = Class.new(parent) do
        def self.name = "OverrideChild"
        param :per_page, default: 100
      end

      expect(child.params.keys).to eq(%i[region per_page])
      expect(child.params[:per_page]).to eq(default: 100)
      expect(parent.params[:per_page]).to eq(default: 25)
    end

    it "softens a required hand-off with a default" do
      strict_parent = Class.new(base_class) do
        def self.name = "StrictParent"
        receives :order
      end
      softened = Class.new(strict_parent) do
        def self.name = "SoftenedChild"
        receives :order, default: nil
      end

      expect(softened.received_params[:order]).to eq(default: nil)
    end

    it "hardens a defaulted hand-off back to required" do
      soft_parent = Class.new(base_class) do
        def self.name = "SoftParent"
        receives :label, default: nil
      end
      hardened = Class.new(soft_parent) do
        def self.name = "HardenedChild"
        receives :label
      end

      expect(hardened.received_params[:label]).to eq({})
    end

    it "duals, not replaces, across doors" do
      parent = Class.new(base_class) do
        def self.name = "WireParent"
        param :status, default: "all"
      end
      child = Class.new(parent) do
        def self.name = "ReceivingChild"
        receives :status
      end

      # the wire door survives — the key stays routable-making and serialized
      expect(child.params[:status]).to eq(default: "all")
      expect(child.received_params.keys).to eq(%i[status])
    end
  end

  describe ".derives" do
    it "declares a derivation, separate from the other stores" do
      klass = Class.new(base_class) do
        def self.name = "DerivesTest"
        param :order_id
        derives(:order, &:order_id)
      end

      expect(klass.derived_params.keys).to eq(%i[order])
      expect(klass.params.keys).to eq(%i[order_id])
      expect(klass.received_params.keys).to eq(%i[])
    end

    it "requires a block" do
      expect do
        Class.new(base_class) do
          def self.name = "BlocklessDerives"
          derives :order
        end
      end.to raise_error(Weft::InvalidDefinition, /derives.*:order.*block/)
    end

    it "merges parent and child declarations; a child redeclaration replaces the parent's block" do
      parent = Class.new(base_class) do
        def self.name = "DerivesParent"
        derives(:foo) { |_p| "parent" }
        derives(:bar) { |_p| "bar" }
      end
      child = Class.new(parent) do
        def self.name = "DerivesChild"
        derives(:foo) { |_p| "child" }
      end

      expect(child.derived_params.keys).to eq(%i[foo bar]) # parent's position, child's block
      expect(child.derived_params[:foo][:block]).not_to eq(parent.derived_params[:foo][:block])
      expect(parent.derived_params[:foo][:block].call(nil)).to eq("parent")
      expect(child.derived_params[:foo][:block].call(nil)).to eq("child")
    end

    it "records contextual and override on the declaration" do
      klass = Class.new(base_class) do
        def self.name = "ModedDerives"
        derives(:plain) { |_p| 1 }
        derives(:ctx, contextual: true) { |_p| 2 }
        derives(:owned, override: true) { |_p| 3 }
      end

      expect(klass.derived_params[:plain]).not_to include(:contextual, :override)
      expect(klass.derived_params[:ctx]).to include(contextual: true, override: true)
      expect(klass.derived_params[:owned]).to include(override: true)
      expect(klass.derived_params[:owned]).not_to include(:contextual)
    end

    # Accepting the pair would register a declaration that can never run: it
    # is computed where it is read, and yielding means it is never read.
    it "refuses a contextual derivation that yields to an ancestor" do
      expect do
        Class.new(base_class) do
          def self.name = "YieldingContextual"
          derives(:label, contextual: true, override: false) { |_p| "x" }
        end
      end.to raise_error(Weft::InvalidDefinition, /contextual.*never running/m)
    end
  end

  describe ".defines" do
    it "registers a constant derivation per pair, in the derived store" do
      klass = Class.new(base_class) do
        def self.name = "DefinesTest"
        defines label: "Drivers", accent: "available"
      end

      expect(klass.derived_params.keys).to eq(%i[label accent])
      expect(klass.derived_params[:label][:block].call(nil)).to eq("Drivers")
      expect(klass.derived_params[:accent][:block].call(nil)).to eq("available")
    end

    it "records the declaration site, not the sugar's internals, as the derivation's origin" do
      first = Class.new(base_class) do
        def self.name = "FirstDefiner"
        defines label: "A"
      end
      second = Class.new(base_class) do
        def self.name = "SecondDefiner"
        defines label: "B"
      end

      expect(first.derived_params[:label][:source_location].first).to end_with("params_spec.rb")
      expect(first.derived_params[:label][:source_location]).
        not_to eq(second.derived_params[:label][:source_location])
    end

    # The class axis, which the two verbs do share: both write the same table,
    # so a subclass redeclaring through either replaces what it inherited.
    # (What they no longer share is `override` — see the assembly specs.)
    it "shares one declaration table with derives, so either verb overrides the other" do
      parent = Class.new(base_class) do
        def self.name = "DefinedParent"
        defines label: "static"
      end
      child = Class.new(parent) do
        def self.name = "DerivingChild"
        derives(:label) { |_p| "computed" }
      end

      expect(child.derived_params[:label][:block].call(nil)).to eq("computed")
      expect(parent.derived_params[:label][:block].call(nil)).to eq("static")
    end

    it "registers as overriding, where a plain derives does not" do
      klass = Class.new(base_class) do
        def self.name = "PinningClass"
        defines label: "Drivers"
        derives(:other) { |_p| "computed" }
      end

      expect(klass.derived_params[:label][:override]).to be(true)
      expect(klass.derived_params[:other]).not_to have_key(:override)
    end

    describe "a pinned value is weft's own frozen copy" do
      it "hands out a frozen value, so one render cannot leak into the next" do
        klass = Class.new(base_class) do
          def self.name = "PinnedNav"
          defines nav: ["home"]
        end

        pinned = klass.derived_params[:nav][:block].call(nil)

        expect(pinned).to be_frozen
        expect { pinned << "leaked" }.to raise_error(FrozenError)
      end

      it "never freezes the object it was handed, which the app may also hold" do
        shared = ["home"]
        Class.new(base_class) do
          def self.name = "PinnedFromConstant"
          defines nav: shared
        end

        expect(shared).not_to be_frozen
        expect { shared << "the app's own push" }.not_to raise_error
      end

      it "copies rather than aliases, so the app mutating its own object does not move the pin" do
        shared = ["home"]
        klass = Class.new(base_class) do
          def self.name = "PinnedIndependently"
          defines nav: shared
        end
        shared << "added later"

        expect(klass.derived_params[:nav][:block].call(nil)).to eq(["home"])
      end

      # A Class is the one value kind dup gets wrong: the copy answers its
      # methods but is not the original — `==` is false, `name` is nil, and
      # instances of it are not `is_a?` the real class. Since a Class is
      # already a process-wide shared object, there is nothing for the copy
      # to protect, so it is handed through as itself.
      it "passes a Class through untouched, identity intact" do
        row = Class.new(Weft::Component) { def self.name = "PinnedRowClass" }
        klass = Class.new(base_class) do
          def self.name = "TableWithRowClass"
          defines row_class: row
        end

        expect(klass.derived_params[:row_class][:block].call(nil)).to equal(row)
      end

      it "passes a Module through untouched" do
        flags = Module.new
        klass = Class.new(base_class) do
          def self.name = "PinnedModule"
          defines flags: flags
        end

        expect(klass.derived_params[:flags][:block].call(nil)).to equal(flags)
      end

      it "leaves values that cannot be mutated anyway alone" do
        klass = Class.new(base_class) do
          def self.name = "PinnedScalars"
          defines count: 3, name: :drivers, missing: nil
        end
        blocks = klass.derived_params

        expect(blocks[:count][:block].call(nil)).to eq(3)
        expect(blocks[:name][:block].call(nil)).to eq(:drivers)
        expect(blocks[:missing][:block].call(nil)).to be_nil
      end
    end

    # `defines` takes one bare hash, so a facet keyword written beside a pair
    # becomes a key rather than being refused the way `param` and `derives`
    # refuse it. Both readings are legitimate — someone may genuinely want a
    # key named `type` — so the name alone cannot decide, and the value is
    # what tips it.
    describe "a key that looks like a facet someone meant to declare" do
      it "warns, naming the facet" do
        allow(Weft.logger).to receive(:warn)

        Class.new(base_class) do
          def self.name = "MeantToType"
          defines something: :else, type: :uuid
        end

        expect(Weft.logger).to have_received(:warn).with(/MeantToType.*no keyword options.*:type/m)
      end

      it "stays quiet when the value is plainly a value and not a facet" do
        allow(Weft.logger).to receive(:warn)

        Class.new(base_class) do
          def self.name = "GenuineTypeKey"
          defines type: "mutilator-3000", digest: "sha256", label: "Drivers"
        end

        expect(Weft.logger).not_to have_received(:warn)
      end

      it "warns on a facet-shaped digest or override too" do
        allow(Weft.logger).to receive(:warn)

        Class.new(base_class) do
          def self.name = "MeantToDigest"
          defines label: "x", digest: true, override: true
        end

        expect(Weft.logger).to have_received(:warn).with(/:digest/).once
        expect(Weft.logger).to have_received(:warn).with(/:override/).once
      end

      # `default:` is deliberately not checked: every value is a plausible
      # default, so there is no shape to discriminate on and the check would
      # fire on every key that happened to be named `default`.
      it "does not guess at a key named default, which no value could distinguish" do
        allow(Weft.logger).to receive(:warn)

        Class.new(base_class) do
          def self.name = "DefaultKey"
          defines default: "open"
        end

        expect(Weft.logger).not_to have_received(:warn)
      end
    end
  end

  describe "param DSL" do
    it "declares attributes with defaults" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status, default: "active"
      end

      expect(component_class.params).to eq(status: { default: "active" })
    end

    it "declares attributes without defaults" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :order_id
      end

      expect(component_class.params).to eq(order_id: { default: nil })
    end

    it "accepts an optional type: kwarg" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :page, default: 1, type: :integer
      end

      expect(component_class.params[:page]).to eq(default: 1, type: :integer)
    end

    it "coerces a typed param's wire value by declared type, end to end" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TypedWireCard"
        param :page, type: :integer

        def build(attributes = {})
          super
          text_node params.page.class.name
        end
      end

      html = Weft::Context.new({}, nil, wire_params: { "page" => "2" }) do
        insert_tag(component_class)
      end.to_s

      expect(html).to include("Integer")
    end

    it "accumulates multiple attributes in declaration order" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :order_id
        param :status, default: "pending"
      end

      expect(component_class.params.keys).to eq(%i[order_id status])
    end

    it "inherits parent attributes in subclasses" do
      parent = Class.new(Weft::Component) do
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
      parent = Class.new(Weft::Component) do
        def self.name = "PagedBase"
        param :per_page, default: 25
      end
      child = Class.new(parent) do
        def self.name = "WidePager"
        param :per_page, default: 100
      end
      component = Weft::Context.new { insert_tag(child) }.children.first

      expect(component.params.per_page).to eq(100)
      expect(component.weft_component_url).to eq("/_components/wide_pager?per_page=100")
    end
  end

  describe "receives DSL" do
    it "does not make a component routable" do
      component_class = Class.new(Weft::Component) do
        def self.name = "HandOffOnly"
        receives :order
      end

      expect(component_class.routable?).to be(false)
    end
  end

  describe "derives DSL" do
    it "does not make a component routable" do
      component_class = Class.new(Weft::Component) do
        def self.name = "DeriveOnly"
        derives(:order) { |_p| nil }
      end

      expect(component_class.routable?).to be(false)
    end
  end

  # A hand-off's rank travels. The value a call site staged for a component
  # keeps speaking at level 1 through every branch below that component, so a
  # descendant declaring the same key reads what its ancestor was handed
  # rather than whatever the page happened to be filtered by.
  describe "a hand-off's rank below the component it was staged for" do
    # `param :status` on the descendant is the whole point: an undeclared
    # reader would inherit the value anyway, so only a declaring one can
    # demonstrate the rank.
    let(:badge_class) do
      Class.new(Weft::Component) do
        def self.name = "StatusBadge"
        param :status
        identifies_by :status
      end
    end

    # A descendant with both doors open, so a nearer call site has somewhere to
    # put a value. `extra` adds wire-only keys, for testing what the slot
    # carries alongside the key a nearer site overrode.
    def dual_badge(*extra)
      Class.new(Weft::Component) do
        def self.name = "DualBadge"
        param :status
        receives :status
        extra.each { |key| param key }
      end
    end

    # A card handed :status (and anything in +receiving+) that builds +badge+
    # with +kwargs+. Passing none is the plain nested case.
    def card_handing(badge, kwargs = {}, receiving: %i[status])
      Class.new(Weft::Component) do
        def self.name = "StatusCard"
        receiving.each { |key| receives key }
        define_method(:build) do |attributes = {}|
          super(attributes)
          insert_tag(badge, **kwargs)
        end
      end
    end

    def nested_in(card, badge, wire: {}, **parent_kwargs)
      ctx = Weft::Context.new({}, nil, wire_params: wire) { insert_tag(card, **parent_kwargs) }
      ctx.children.first.children.find { |el| el.is_a?(badge) }
    end

    it "outranks the descendant's own wire value" do
      badge = badge_class
      nested = nested_in(card_handing(badge), badge, wire: { "status" => "archived" },
                                                     status: "shipped")

      expect(nested.params.status).to eq("shipped")
    end

    it "still loses to the descendant's own hand-off — the nearer call site wins" do
      badge = dual_badge
      nested = nested_in(card_handing(badge, { status: "archived" }), badge, status: "shipped")

      expect(nested.params.status).to eq("archived")
    end

    # A nil means "step aside", on both slots, but they step aside from
    # different things and the difference is easy to slur together. A nil
    # overlay suppresses the wire and resolution continues at inherited; a nil
    # hand-off suppresses the hand-off and resolution continues at the
    # descendant's own wire. Pinned because two parallel slots invite the
    # assumption that they behave alike.
    it "lets a nil at a nearer call site step aside for the descendant's own wire" do
      badge = dual_badge
      nested = nested_in(card_handing(badge, { status: nil }), badge,
                         wire: { "status" => "from-wire" }, status: "handed")

      expect(nested.params.status).to eq("from-wire")
    end

    it "carries only the keys nobody nearer mentioned" do
      badge = dual_badge(:region)
      card = card_handing(badge, { status: "archived" }, receiving: %i[status region])
      nested = nested_in(card, badge, wire: { "region" => "from-wire" },
                                      status: "shipped", region: "west")

      expect(nested.params.status).to eq("archived")
      expect(nested.params.region).to eq("west")
    end

    # The shape this mission exists for. Four cards from one collection, each
    # handed its own status, each building a badge that identifies by it. The
    # page carrying its own filter used to collapse all four badges onto one
    # value and therefore one DOM id, which is an invalid document and not
    # merely a wrong reading.
    describe "a collection of siblings, each handed its own value" do
      let(:row_class) do
        badge = badge_class
        card = card_building_with_own_status(badge)
        Class.new(Weft::Component) do
          def self.name = "StatusRow"
          define_method(:build) do |attributes = {}|
            super(attributes)
            %w[new picked shipped delivered].each { |s| insert_tag(card, status: s) }
          end
        end
      end

      def card_building_with_own_status(badge)
        Class.new(Weft::Component) do
          def self.name = "RowCard"
          receives :status
          identifies_by :status
          define_method(:build) do |attributes = {}|
            super(attributes)
            insert_tag(badge)
          end
        end
      end

      def badges_under(row, badge, wire)
        ctx = Weft::Context.new({}, nil, wire_params: wire) { insert_tag(row) }
        ctx.children.first.children.map { |card| card.children.find { |el| el.is_a?(badge) } }
      end

      it "keeps each badge on its own card's value while the page carries a filter" do
        badges = badges_under(row_class, badge_class, { "status" => "shipped" })

        expect(badges.map { |b| b.params.status }).to eq(%w[new picked shipped delivered])
      end

      it "gives each badge its own DOM id, so all four are addressable" do
        badges = badges_under(row_class, badge_class, { "status" => "shipped" })

        expect(badges.map(&:weft_dom_id).uniq.size).to eq(4)
      end

      it "stops emitting the duplicate-id warning it used to provoke" do
        allow(Weft.logger).to receive(:warn)

        badges_under(row_class, badge_class, { "status" => "shipped" }).each(&:weft_dom_id)

        expect(Weft.logger).not_to have_received(:warn).with(/StatusBadge rendered more than once/)
      end
    end
  end

  describe "serialization projection" do
    let(:order) { Struct.new(:id, :name).new(9, "Crate") }

    it "serializes own wire params only into weft_component_url — hand-offs stay server-side" do
      klass = Class.new(Weft::Component) do
        def self.name = "ManifestCard"
        param :status
        receives :order
      end
      handed = order
      component = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) do
        insert_tag(klass, order: handed)
      end.children.first

      expect(component.weft_component_url).to eq("/_components/manifest_card?status=hot")
    end

    it "keeps inherited values out of weft_component_url" do
      parent_class = Class.new(Weft::Component) do
        def self.name = "UrlParent"
        param :region, default: "west"
      end
      child_class = Class.new(Weft::Component) do
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
      expect(child.weft_component_url).to eq("/_components/url_child?status=open")
    end

    it "serializes a handed value through its wire dual — the refresh keeps it" do
      klass = Class.new(Weft::Component) do
        def self.name = "DualCard"
        param :status
        receives :status
      end
      component = Weft::Context.new { insert_tag(klass, status: "fresh") }.children.first

      expect(component.weft_component_url).to eq("/_components/dual_card?status=fresh")
    end

    it "derives weft_dom_id from own wire params only, never a hand-off" do
      klass = Class.new(Weft::Component) do
        def self.name = "SlipCard"
        receives :order
      end
      handed = order
      component = Weft::Context.new { insert_tag(klass, order: handed) }.children.first

      expect(component.weft_dom_id).to eq("slip-card")
    end

    it "keeps hand-offs out of the SSE stream URL" do
      klass = Class.new(Weft::Component) do
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

  # Strictness and requiredness are refused at CONSTRUCTION, not inside the
  # Resolver — the Resolver reports, the component commits. That split is what
  # lets the error path re-read the same malformed wire hash while reporting
  # the failure, instead of raising a second time on top of it.
  describe "refusing wire values a declaration cannot accept" do
    def build(klass, wire)
      Weft::Context.new({}, nil, wire_params: wire) { insert_tag(klass) }.children.first
    end

    it "refuses a value the declared type cannot represent" do
      klass = Class.new(Weft::Component) do
        def self.name = "StrictBuild"
        param :page, default: 1, type: :integer
      end

      expect { build(klass, { "page" => "wombat" }) }.
        to raise_error(Weft::InvalidParamValue, /wombat.*:page/m)
    end

    # Each type says what it wanted in words, because "declares type :uuid"
    # tells a reader only what they already wrote. This is also the facet a
    # registered type needs most: a `:duration` has to be able to say "is not
    # an ISO-8601 duration" rather than inherit something generic.
    it "says what the type wanted, in the type's own words" do
      {
        integer: "whole number", float: "number", decimal: "number",
        boolean: "true or false", string: "single value", uuid: "uuid"
      }.each do |type, phrase|
        klass = Class.new(Weft::Component) do
          def self.name = "RefusalProbe"
          param :probe, type: type
        end
        bad = type == :string ? %w[a b] : "wombat"

        expect { build(klass, { "probe" => bad }) }.
          to raise_error(Weft::InvalidParamValue, /#{Regexp.escape(phrase)}/), type.to_s
      end
    end

    it "answers 400, since the request is unreadable rather than unacceptable" do
      klass = Class.new(Weft::Component) do
        def self.name = "StatusBuild"
        param :page, type: :integer
      end

      error = begin
        build(klass, { "page" => "wombat" })
      rescue Weft::InvalidParamValue => e
        e
      end

      expect(error).to be_a(Weft::BadRequest)
      expect(error.status).to eq(400)
    end

    # The whole point of refusing rather than fabricating is to be able to say
    # what arrived. A recovery redrawing a form needs "wombat" back, not the 0
    # that lenient coercion would have invented.
    it "carries every violation, with the raw value the user actually sent" do
      klass = Class.new(Weft::Component) do
        def self.name = "CarriesBuild"
        param :page, type: :integer
        param :rate, type: :float
      end

      error = begin
        build(klass, { "page" => "wombat", "rate" => "badger" })
      rescue Weft::InvalidParamValue => e
        e
      end

      expect(error.violations.map(&:key)).to eq(%i[page rate])
      expect(error.violations.map(&:raw)).to eq(%w[wombat badger])
    end

    it "refuses an absent value on a required param" do
      klass = Class.new(Weft::Component) do
        def self.name = "RequiredBuild"
        param :order_id, type: :uuid, required: true
      end

      expect { build(klass, {}) }.to raise_error(Weft::MissingParam, /order_id/)
    end

    it "accepts a required param the wire supplied" do
      klass = Class.new(Weft::Component) do
        def self.name = "RequiredSupplied"
        param :page, type: :integer, required: true
      end

      expect(build(klass, { "page" => "2" }).params.page).to eq(2)
    end

    # `required:` guards the absence door and `strict:` the malformation door.
    # A malformed value is not an absent one, so it is one complaint, not two.
    it "reports a malformed required value as malformed, not as missing" do
      klass = Class.new(Weft::Component) do
        def self.name = "RequiredMalformed"
        param :page, type: :integer, required: true
      end

      expect { build(klass, { "page" => "wombat" }) }.to raise_error(Weft::InvalidParamValue)
    end

    it "refuses a default alongside required at declare time" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "RequiredWithDefault"
          param :page, default: 1, type: :integer, required: true
        end
      end.to raise_error(Weft::InvalidDefinition, /required.*default/m)
    end
  end
end
