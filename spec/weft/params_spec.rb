# frozen_string_literal: true

RSpec.describe Weft::Params do
  subject(:params) { described_class.new({ status: "shipped", count: 42, label: nil }) }

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

  describe "declared defaults as read-time fallbacks" do
    subject(:params) { described_class.new({ view: nil, page: 2 }, defaults: { view: "all", page: 1 }) }

    it "answers with the default when no source supplied the key" do
      expect(params[:view]).to eq("all")
      expect(params.view).to eq("all")
    end

    it "leaves a supplied value alone" do
      expect(params[:page]).to eq(2)
    end

    it "counts a defaulted key as present" do
      expect(params.key?(:view)).to be(true)
    end

    it "materializes defaults into to_h" do
      expect(params.to_h).to eq(view: "all", page: 2)
    end

    it "does not hand defaults to a branch — a fallback belongs to whoever declared it" do
      expect(params.branch_data).to eq(page: 2)
    end

    it "carries its defaults across a non-crossing branch, and the delta with them" do
      branched = params % { page: 9 }

      expect(branched[:view]).to eq("all")
      expect(branched[:page]).to eq(9)
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
      no_count = described_class.new({ status: "shipped" })
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
      bag = described_class.new({ order: thunk { |_p| runs += 1 } })

      expect(bag.key?(:order)).to be(true)
      expect(runs).to eq(0)
    end

    it "forces on first read and memoizes" do
      runs = 0
      bag = described_class.new({ order: thunk do |_p|
        runs += 1
        "found"
      end })

      expect(bag.order).to eq("found")
      expect(bag[:order]).to eq("found")
      expect(runs).to eq(1)
    end

    it "hands the bag itself to the block, so derivations can chain lazily" do
      runs = []
      bag = described_class.new({
                                  order_id: 42,
                                  order: thunk do |p|
                                    runs << :order
                                    "order-#{p.order_id}"
                                  end,
                                  summary: thunk do |p|
                                    runs << :summary
                                    "sum(#{p.order})"
                                  end
                                })

      expect(bag.summary).to eq("sum(order-42)")
      expect(runs).to eq(%i[summary order])
    end

    it "forces blocks in a sandbox self with no component state in reach" do
      bag = described_class.new(
        { selfish: described_class::Thunk.new(proc { |_p| some_component_method }) }
      )

      expect { bag.selfish }.to raise_error(NameError, /some_component_method/)
    end

    it "gives each derivation a fresh sandbox, so scratch ivars don't leak between them" do
      bag = described_class.new(
        { writes: described_class::Thunk.new(proc { |_p| @stash = 1 }),
          reads: described_class::Thunk.new(proc { |_p| instance_variable_defined?(:@stash) }) }
      )

      expect(bag.writes).to eq(1)
      expect(bag.reads).to be(false)
    end

    it "raises a clear error on circular derivation instead of overflowing" do
      bag = described_class.new(
        { a: thunk(&:b), b: thunk(&:a) }
      )

      expect { bag.a }.to raise_error(Weft::InvalidUsage, /circular/i)
    end

    it "surfaces a failing derivation at read time, not registration" do
      bag = described_class.new({ order: thunk { |_p| raise "boom" } })

      expect(bag.key?(:order)).to be(true)
      expect { bag.order }.to raise_error(RuntimeError, "boom")
    end

    it "materializes everything for to_h and Hash-API delegation" do
      bag = described_class.new({ status: "hot", order: thunk { |_p| "forced" } })

      expect(bag.to_h).to eq(status: "hot", order: "forced")
      expect(described_class.new({ n: thunk { |_p| 5 } }).map { |k, v| [k, v] }).to eq([[:n, 5]])
    end
  end

  describe "the hash API against unforced derivations" do
    def thunk(&block) = described_class::Thunk.new(block)

    it "answers keys without forcing anything" do
      runs = 0
      bag = described_class.new({ status: "hot", order: thunk { |_p| runs += 1 } })

      expect(bag.keys).to eq(%i[status order])
      expect(runs).to eq(0)
    end

    it "includes keys that only a declared default supplies" do
      klass = Class.new(Weft::Component) do
        def self.name = "DefaultedKeys"
        param :status, default: "hot"
      end

      expect(Weft::Params::Assembly.for_request(klass, {}).keys).to eq([:status])
    end

    it "stops forcing as soon as any? is satisfied" do
      runs = []
      bag = described_class.new({ first: thunk { |_p| runs << :first and true },
                                  second: thunk { |_p| runs << :second and true } })

      expect(bag.any? { |_k, v| v }).to be(true)
      expect(runs).to eq([:first])
    end

    it "still forces everything when any? is never satisfied" do
      runs = []
      bag = described_class.new({ a: thunk { |_p| runs << :a and false },
                                  b: thunk { |_p| runs << :b and false } })

      expect(bag.any? { |_k, v| v }).to be(false)
      expect(runs).to eq(%i[a b])
    end

    # keys is answered from the declarations, so a poisoned derivation is no
    # obstacle to asking what the bag holds.
    it "answers keys on a bag whose derivation has failed" do
      bag = described_class.new({ ok: 1, bad: thunk { |_p| raise "poisoned" } })

      expect { bag.bad }.to raise_error(RuntimeError)
      expect(bag.keys).to eq(%i[ok bad])
    end

    it "lets a declared param named keys win over the hash API" do
      klass = Class.new(Weft::Component) do
        def self.name = "KeysParam"
        param :keys, default: "mine"
      end

      expect(Weft::Params::Assembly.for_request(klass, {}).keys).to eq("mine")
    end

    it "lets a declared param named to_h win over the hash API" do
      klass = Class.new(Weft::Component) do
        def self.name = "ToHParam"
        param :to_h, default: "mine"
      end

      expect(Weft::Params::Assembly.for_request(klass, {}).to_h).to eq("mine")
    end
  end

  describe "reporting derivations that have failed" do
    def thunk(&block) = described_class::Thunk.new(block)

    def errors_in(bag) = bag.send(:derivation_errors)

    it "reports nothing while every derivation is unforced" do
      bag = described_class.new({ order: thunk { |_p| raise "boom" } })

      expect(errors_in(bag)).to eq({})
    end

    it "reports the exception once a derivation has failed" do
      bag = described_class.new({ order: thunk { |_p| raise "lookup exploded" } })

      expect { bag.order }.to raise_error(RuntimeError)

      expect(errors_in(bag).keys).to eq([:order])
      expect(errors_in(bag)[:order]).to be_a(RuntimeError)
      expect(errors_in(bag)[:order].message).to eq("lookup exploded")
    end

    it "leaves a derivation that succeeded out of the report" do
      bag = described_class.new({ ok: thunk { |_p| "fine" }, bad: thunk { |_p| raise "no" } })

      bag.ok
      expect { bag.bad }.to raise_error(RuntimeError)

      expect(errors_in(bag).keys).to eq([:bad])
    end

    it "ignores plain values, which cannot have failed" do
      bag = described_class.new({ status: "hot" })

      expect(errors_in(bag)).to eq({})
    end

    # A branch shares the thunk object, so a failure anywhere in the lineage is
    # the same failure everywhere it reaches — no registry, just identity.
    it "sees a failure a branch caused, because the thunk is one object" do
      poisoned = thunk { |_p| raise "boom" }
      parent = described_class.new({ order: poisoned })
      child = described_class.new(parent.branch_data)

      expect { child.order }.to raise_error(RuntimeError)

      expect(errors_in(parent).keys).to eq([:order])
    end

    # Private on purpose: a real public method would never reach method_missing,
    # so it would shadow a param of the same name — the defect this avoids.
    it "does not shadow a declared param of the same name" do
      klass = Class.new(Weft::Component) do
        def self.name = "ShadowProbe"
        param :derivation_errors, default: "mine"
      end
      bag = Weft::Params::Assembly.for_request(klass, {})

      expect(bag.derivation_errors).to eq("mine")
    end
  end
end
