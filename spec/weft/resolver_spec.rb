# frozen_string_literal: true

RSpec.describe Weft::Resolver do
  subject(:resolver) { described_class.new }

  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "TestComponent"
      attribute :status, default: "pending"
      attribute :count, default: 0
      attribute :rate, default: 1.5
      attribute :active, default: true
      attribute :label
    end
  end

  describe "#resolve" do
    it "maps string params to attributes using declared defaults for coercion" do
      result = resolver.resolve(component_class, "status" => "shipped", "count" => "42")

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(42)
    end

    it "coerces integers from string params when default is Integer" do
      result = resolver.resolve(component_class, "count" => "7")
      expect(result[:count]).to eq(7)
    end

    it "coerces floats from string params when default is Float" do
      result = resolver.resolve(component_class, "rate" => "3.14")
      expect(result[:rate]).to eq(3.14)
    end

    it "coerces booleans from string params when default is true" do
      result = resolver.resolve(component_class, "active" => "false")
      expect(result[:active]).to be(false)
    end

    it "coerces booleans from string params when default is false" do
      klass = Class.new(Weft::Component) do
        def self.name = "BoolTest"
        attribute :disabled, default: false
      end

      result = resolver.resolve(klass, "disabled" => "true")
      expect(result[:disabled]).to be(true)
    end

    it "passes strings through when default is nil" do
      result = resolver.resolve(component_class, "label" => "hello")
      expect(result[:label]).to eq("hello")
    end

    it "passes strings through when default is a String" do
      result = resolver.resolve(component_class, "status" => "active")
      expect(result[:status]).to eq("active")
    end

    it "passes Hash values through without coercion" do
      klass = Class.new(Weft::Component) do
        def self.name = "HashTest"
        attribute :items
      end

      result = resolver.resolve(klass, "items" => { "widget" => "3", "gadget" => "1" })
      expect(result[:items]).to eq("widget" => "3", "gadget" => "1")
    end

    it "passes Array values through without coercion" do
      klass = Class.new(Weft::Component) do
        def self.name = "ArrayTest"
        attribute :tags
      end

      result = resolver.resolve(klass, "tags" => %w[a b c])
      expect(result[:tags]).to eq(%w[a b c])
    end

    it "applies defaults for missing params" do
      result = resolver.resolve(component_class, {})

      expect(result[:status]).to eq("pending")
      expect(result[:count]).to eq(0)
      expect(result[:rate]).to eq(1.5)
      expect(result[:active]).to be(true)
      expect(result[:label]).to be_nil
    end

    it "ignores params not declared as attributes" do
      result = resolver.resolve(component_class, "status" => "shipped", "unknown" => "ignored")

      expect(result).not_to have_key(:unknown)
      expect(result.keys).to match_array(%i[status count rate active label])
    end

    it "accepts symbol keys as well as string keys" do
      result = resolver.resolve(component_class, status: "shipped", count: "5")

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(5)
    end
  end
end
