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

    it "accepts optional type: kwarg" do
      klass = Class.new(base_class) do
        def self.name = "TypedAttr"
        param :page, default: 1, type: :integer
      end

      expect(klass.params[:page]).to eq(default: 1, type: :integer)
    end

    it "accepts all five declarable types" do
      klass = Class.new(base_class) do
        def self.name = "AllTypesTest"
        param :label, type: :string
        param :page, type: :integer
        param :rate, type: :float
        param :active, type: :boolean
        param :price, type: :decimal
      end

      expect(klass.params.values.map { |meta| meta[:type] }).
        to eq(%i[string integer float boolean decimal])
    end

    it "raises InvalidDefinition on an unknown type" do
      expect do
        Class.new(base_class) do
          def self.name = "UnknownTypeTest"
          param :page, type: :number
        end
      end.to raise_error(Weft::InvalidDefinition,
                         /:page.*unknown type :number.*:string, :integer, :float, :boolean, :decimal/m)
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

    it "is just derives: a child redeclaration through either verb replaces the other's" do
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
      expect(component.weft_url).to eq("/_components/wide_pager?per_page=100")
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

  describe "serialization projection" do
    let(:order) { Struct.new(:id, :name).new(9, "Crate") }

    it "serializes own wire params only into weft_url — hand-offs stay server-side" do
      klass = Class.new(Weft::Component) do
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
      expect(child.weft_url).to eq("/_components/url_child?status=open")
    end

    it "serializes a handed value through its wire dual — the refresh keeps it" do
      klass = Class.new(Weft::Component) do
        def self.name = "DualCard"
        param :status
        receives :status
      end
      component = Weft::Context.new { insert_tag(klass, status: "fresh") }.children.first

      expect(component.weft_url).to eq("/_components/dual_card?status=fresh")
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
end
