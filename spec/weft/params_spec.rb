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

  describe "thunks (lazy entries)" do
    def thunk(&block)
      described_class::Thunk.new(block)
    end

    it "occupies its key without running" do
      runs = 0
      bag = described_class.new(order: thunk { |_p| runs += 1 })

      expect(bag.key?(:order)).to be(true)
      expect(runs).to eq(0)
    end

    it "forces on first read and memoizes" do
      runs = 0
      bag = described_class.new(order: thunk do |_p|
        runs += 1
        "found"
      end)

      expect(bag.order).to eq("found")
      expect(bag[:order]).to eq("found")
      expect(runs).to eq(1)
    end

    it "hands the bag itself to the block, so derivations can chain lazily" do
      runs = []
      bag = described_class.new(
        order_id: 42,
        order: thunk do |p|
          runs << :order
          "order-#{p.order_id}"
        end,
        summary: thunk do |p|
          runs << :summary
          "sum(#{p.order})"
        end
      )

      expect(bag.summary).to eq("sum(order-42)")
      expect(runs).to eq(%i[summary order])
    end

    it "runs blocks against a void self" do
      bag = described_class.new(
        selfish: described_class::Thunk.new(proc { |_p| some_component_method }),
        stateful: described_class::Thunk.new(proc { |_p| @stash = 1 })
      )

      expect { bag.selfish }.to raise_error(NameError, /some_component_method/)
      expect { bag.stateful }.to raise_error(FrozenError)
    end

    it "raises a clear error on circular derivation instead of overflowing" do
      bag = described_class.new(
        a: thunk(&:b),
        b: thunk(&:a)
      )

      expect { bag.a }.to raise_error(Weft::InvalidUsage, /circular/i)
    end

    it "surfaces a failing derivation at read time, not registration" do
      bag = described_class.new(order: thunk { |_p| raise "boom" })

      expect(bag.key?(:order)).to be(true)
      expect { bag.order }.to raise_error(RuntimeError, "boom")
    end

    it "materializes everything for to_h and Hash-API delegation" do
      bag = described_class.new(status: "hot", order: thunk { |_p| "forced" })

      expect(bag.to_h).to eq(status: "hot", order: "forced")
      expect(described_class.new(n: thunk { |_p| 5 }).map { |k, v| [k, v] }).to eq([[:n, 5]])
    end
  end
end
