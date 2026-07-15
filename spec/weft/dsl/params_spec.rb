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
end
