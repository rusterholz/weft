# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Weft::Resolver do
  subject(:resolver) { described_class }

  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "TestComponent"
      param :status, default: "pending", type: :string
      param :count, default: 0, type: :integer
      param :rate, default: 1.5, type: :float
      param :active, default: true, type: :boolean
      param :price, type: :decimal
      param :label
    end
  end

  describe ".resolve" do
    it "coerces wire strings into their declared types" do
      result = resolver.resolve(
        component_class,
        "status" => "shipped", "count" => "42", "rate" => "3.14",
        "active" => "false", "price" => "19.99"
      )

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(42)
      expect(result[:rate]).to eq(3.14)
      expect(result[:active]).to be(false)
      expect(result[:price]).to eq(BigDecimal("19.99"))
    end

    it "coerces :decimal with full precision, not through Float" do
      result = resolver.resolve(component_class, "price" => "0.1")

      expect(result[:price]).to be_a(BigDecimal)
      expect(result[:price]).to eq(BigDecimal("0.1"))
    end

    it "maps only \"true\" and \"1\" to true for :boolean" do
      expect(resolver.resolve(component_class, "active" => "true")[:active]).to be(true)
      expect(resolver.resolve(component_class, "active" => "1")[:active]).to be(true)
      expect(resolver.resolve(component_class, "active" => "yes")[:active]).to be(false)
    end

    it "coerces :string with to_s, so a rich pseudo-wire value becomes a string" do
      result = resolver.resolve(component_class, "status" => :shipped)

      expect(result[:status]).to eq("shipped")
    end

    it "never coerces an untyped param, even when its default looks typed" do
      klass = Class.new(Weft::Component) do
        def self.name = "UntypedTest"
        param :page, default: 1
        param :flag, default: false
      end

      result = resolver.resolve(klass, "page" => "2", "flag" => "true")

      expect(result[:page]).to eq("2")
      expect(result[:flag]).to eq("true")
    end

    it "passes rich values (Hash, Array) through untyped params unchanged" do
      klass = Class.new(Weft::Component) do
        def self.name = "RichTest"
        param :items
        param :tags
      end

      result = resolver.resolve(klass, "items" => { "widget" => "3" }, "tags" => %w[a b])

      expect(result[:items]).to eq("widget" => "3")
      expect(result[:tags]).to eq(%w[a b])
    end

    it "applies defaults for missing params without coercing them" do
      result = resolver.resolve(component_class, {})

      expect(result[:status]).to eq("pending")
      expect(result[:count]).to eq(0)
      expect(result[:rate]).to eq(1.5)
      expect(result[:active]).to be(true)
      expect(result[:price]).to be_nil
      expect(result[:label]).to be_nil
    end

    it "ignores params not declared" do
      result = resolver.resolve(component_class, "status" => "shipped", "unknown" => "ignored")

      expect(result).not_to have_key(:unknown)
      expect(result.keys).to match_array(%i[status count rate active price label])
    end

    it "accepts symbol keys as well as string keys" do
      result = resolver.resolve(component_class, status: "shipped", count: "5")

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(5)
    end

    it "treats a literal false under a string key as present, not absent" do
      result = resolver.resolve(component_class, "active" => false)

      expect(result[:active]).to be(false)
    end

    it "treats a literal false under a symbol key as present, not absent" do
      result = resolver.resolve(component_class, active: false)

      expect(result[:active]).to be(false)
    end
  end

  describe ".resolve_present" do
    it "coerces only the keys on the wire, without default fill" do
      result = resolver.resolve_present(component_class, "count" => "7")

      expect(result).to eq(count: 7)
    end

    it "treats a literal false under a string key as present" do
      result = resolver.resolve_present(component_class, "active" => false)

      expect(result).to eq(active: false)
    end
  end
end
