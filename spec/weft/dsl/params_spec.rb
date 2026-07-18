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
end
