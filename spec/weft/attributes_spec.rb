# frozen_string_literal: true

RSpec.describe Weft::Attributes do
  subject(:attrs) { described_class.new(status: "shipped", count: 42, label: nil) }

  describe ".extract_from" do
    let(:schema) { { status: { default: "pending" }, count: { default: 0 } } }

    it "extracts declared keys from the raw hash" do
      result = described_class.extract_from({ status: "shipped", count: 42 }, using: schema)
      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(42)
    end

    it "applies defaults for missing keys" do
      result = described_class.extract_from({}, using: schema)
      expect(result[:status]).to eq("pending")
      expect(result[:count]).to eq(0)
    end

    it "does not mutate the raw hash" do
      raw = { status: "shipped", class: "big" }
      described_class.extract_from(raw, using: schema)
      expect(raw).to eq(status: "shipped", class: "big")
    end

    it "returns a Weft::Attributes instance" do
      result = described_class.extract_from({}, using: schema)
      expect(result).to be_a(described_class)
    end
  end

  describe "#[]" do
    it "returns values by symbol key" do
      expect(attrs[:status]).to eq("shipped")
      expect(attrs[:count]).to eq(42)
    end

    it "returns nil for nil-valued keys" do
      expect(attrs[:label]).to be_nil
    end

    it "returns nil for unknown keys" do
      expect(attrs[:nonexistent]).to be_nil
    end
  end

  describe "#key?" do
    it "returns true for declared keys" do
      expect(attrs.key?(:status)).to be(true)
      expect(attrs.key?(:label)).to be(true) # even when value is nil
    end

    it "returns false for undeclared keys" do
      expect(attrs.key?(:nonexistent)).to be(false)
    end
  end

  describe "method-style access (declared attribute wins)" do
    it "returns the attribute value when the method name is a declared key" do
      expect(attrs.status).to eq("shipped")
      expect(attrs.count).to eq(42)
    end

    it "returns nil when the declared key's value is nil" do
      expect(attrs.label).to be_nil
    end

    it "respects declared attributes over Hash methods of the same name" do
      # count is a Hash method but here it's a declared attribute — attribute wins
      expect(attrs.count).to eq(42)
    end
  end

  describe "delegation to the underlying hash (attribute not declared)" do
    it "delegates Hash enumerable methods to the underlying data" do
      expect(attrs.each_pair.to_a).to contain_exactly([:status, "shipped"], [:count, 42], [:label, nil])
    end

    it "delegates compact to the underlying hash" do
      result = attrs.compact
      expect(result).to eq(status: "shipped", count: 42)
    end

    it "delegates map to the underlying hash" do
      collected = attrs.map { |k, v| [k, v] }
      expect(collected).to contain_exactly([:status, "shipped"], [:count, 42], [:label, nil])
    end

    it "supports any? as a Hash method" do
      expect(attrs.any? { |_k, v| v == "shipped" }).to be(true)
    end
  end

  describe "collision resolution example" do
    it "a declared :count attribute shadows Hash#count" do
      # attrs.count returns 42 (the attribute), not 3 (the hash size)
      expect(attrs.count).to eq(42)
    end

    it "a non-colliding hash method still works when no attribute shadows it" do
      no_count = described_class.new(status: "shipped")
      # count isn't declared, so Hash#count takes effect
      expect(no_count.count).to eq(1)
    end
  end

  describe "#to_h" do
    it "returns the underlying hash" do
      expect(attrs.to_h).to eq(status: "shipped", count: 42, label: nil)
    end

    it "always returns a plain hash even when attribute names collide" do
      # explicit fallback when you want the hash regardless of declared attrs
      expect(attrs.to_h[:count]).to eq(42)
      expect(attrs.to_h.count).to eq(3)
    end
  end

  describe "#respond_to?" do
    it "returns true for declared keys" do
      expect(attrs.respond_to?(:status)).to be(true)
    end

    it "returns true for inherited Hash methods" do
      expect(attrs.respond_to?(:select)).to be(true)
      expect(attrs.respond_to?(:each)).to be(true)
    end

    it "returns false for methods that don't exist on Hash and aren't declared keys" do
      expect(attrs.respond_to?(:truly_unknown_method)).to be(false)
    end
  end
end
