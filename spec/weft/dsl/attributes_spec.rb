# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Attributes do
  # Test the mixin on a plain class (not Component/Page) to isolate it.
  let(:base_class) do
    Class.new(Arbre::Component) do
      include Weft::DSL::Attributes

      def self.name = "DslTestBase"
    end
  end

  describe ".attribute" do
    it "declares attributes with defaults" do
      klass = Class.new(base_class) do
        def self.name = "AttrTest"
        attribute :status, default: "active"
      end

      expect(klass.attributes).to eq(status: { default: "active" })
    end

    it "accepts optional type: kwarg" do
      klass = Class.new(base_class) do
        def self.name = "TypedAttr"
        attribute :page, default: 1, type: :integer
      end

      expect(klass.attributes[:page]).to eq(default: 1, type: :integer)
    end
  end

  describe ".attributes inheritance" do
    it "merges parent and child attributes" do
      parent = Class.new(base_class) do
        def self.name = "AttrParent"
        attribute :status
      end
      child = Class.new(parent) do
        def self.name = "AttrChild"
        attribute :priority, default: "low"
      end

      expect(child.attributes.keys).to eq(%i[status priority])
      expect(parent.attributes.keys).to eq(%i[status])
    end
  end
end
