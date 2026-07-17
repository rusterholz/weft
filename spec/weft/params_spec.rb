# frozen_string_literal: true

RSpec.describe Weft::Params do
  subject(:params) { described_class.new(status: "shipped", count: 42, label: nil) }

  describe "#[]" do
    it "returns values by symbol key" do
      expect(params[:status]).to eq("shipped")
      expect(params[:count]).to eq(42)
    end

    it "returns nil for nil-valued keys" do
      expect(params[:label]).to be_nil
    end

    it "returns nil for unknown keys" do
      expect(params[:nonexistent]).to be_nil
    end
  end

  describe "#key?" do
    it "returns true for declared keys" do
      expect(params.key?(:status)).to be(true)
      expect(params.key?(:label)).to be(true) # even when value is nil
    end

    it "returns false for undeclared keys" do
      expect(params.key?(:nonexistent)).to be(false)
    end
  end

  describe "method-style access (declared param wins)" do
    it "returns the param value when the method name is a declared key" do
      expect(params.status).to eq("shipped")
      expect(params.count).to eq(42)
    end

    it "returns nil when the declared key's value is nil" do
      expect(params.label).to be_nil
    end

    it "respects declared attributes over Hash methods of the same name" do
      # count is a Hash method but here it's a declared param — param wins
      expect(params.count).to eq(42)
    end
  end

  describe "delegation to the underlying hash (param not declared)" do
    it "delegates Hash enumerable methods to the underlying data" do
      expect(params.each_pair.to_a).to contain_exactly([:status, "shipped"], [:count, 42], [:label, nil])
    end

    it "delegates compact to the underlying hash" do
      result = params.compact
      expect(result).to eq(status: "shipped", count: 42)
    end

    it "delegates map to the underlying hash" do
      collected = params.map { |k, v| [k, v] }
      expect(collected).to contain_exactly([:status, "shipped"], [:count, 42], [:label, nil])
    end

    it "supports any? as a Hash method" do
      expect(params.any? { |_k, v| v == "shipped" }).to be(true)
    end
  end

  describe "collision resolution example" do
    it "a declared :count param shadows Hash#count" do
      # params.count returns 42 (the param), not 3 (the hash size)
      expect(params.count).to eq(42)
    end

    it "a non-colliding hash method still works when no param shadows it" do
      no_count = described_class.new(status: "shipped")
      # count isn't declared, so Hash#count takes effect
      expect(no_count.count).to eq(1)
    end
  end

  describe "#to_h" do
    it "returns the underlying hash" do
      expect(params.to_h).to eq(status: "shipped", count: 42, label: nil)
    end

    it "always returns a plain hash even when param names collide" do
      # explicit fallback when you want the hash regardless of declared params
      expect(params.to_h[:count]).to eq(42)
      expect(params.to_h.count).to eq(3)
    end
  end

  describe "#respond_to?" do
    it "returns true for declared keys" do
      expect(params.respond_to?(:status)).to be(true)
    end

    it "returns true for inherited Hash methods" do
      expect(params.respond_to?(:select)).to be(true)
      expect(params.respond_to?(:each)).to be(true)
    end

    it "returns false for methods that don't exist on Hash and aren't declared keys" do
      expect(params.respond_to?(:truly_unknown_method)).to be(false)
    end
  end
end
