# frozen_string_literal: true

require "arbre"

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
end
