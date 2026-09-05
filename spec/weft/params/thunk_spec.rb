# frozen_string_literal: true

require "spec_helper"

RSpec.describe Weft::Params::Thunk do
  def bag(data = {}) = Weft::Params.new(data)

  describe "forcing an outcome exactly once" do
    it "runs the block on the first read and returns its result" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and "found" })

      expect(thunk.value(bag)).to eq("found")
      expect(runs).to eq(1)
    end

    it "does not run the block again on a second read" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 })

      thunk.value(bag)
      thunk.value(bag)

      expect(runs).to eq(1)
    end

    # nil is a value a derivation can legitimately produce, so absence needs a
    # sentinel of its own — otherwise "it resolved to nothing" and "it hasn't
    # run" are the same state and the block runs on every read.
    it "memoizes a nil result rather than treating it as unforced" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and nil })

      expect(thunk.value(bag)).to be_nil
      expect(thunk.value(bag)).to be_nil
      expect(runs).to eq(1)
    end

    it "memoizes a false result too" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and false })

      expect(thunk.value(bag)).to be(false)
      expect(thunk.value(bag)).to be(false)
      expect(runs).to eq(1)
    end

    it "yields the reading bag to the block" do
      thunk = described_class.new(proc { |p| "order-#{p.order_id}" })

      expect(thunk.value(bag(order_id: 42))).to eq("order-42")
    end

    it "runs the block in a sandbox self, as forcing through a bag does" do
      thunk = described_class.new(proc { |_p| some_component_method })

      expect { thunk.value(bag) }.to raise_error(NameError, /some_component_method/)
    end
  end

  describe "forcing that fails" do
    it "re-raises the error out of the first read" do
      thunk = described_class.new(proc { |_p| raise "boom" })

      expect { thunk.value(bag) }.to raise_error(RuntimeError, "boom")
    end

    # The mission's whole point: an outcome is settled once. A failure that
    # re-ran would put the double execution back on the least-expected path.
    it "re-raises the very same exception on every later read, without re-running" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and raise "boom" })

      first = nil
      second = nil
      expect { thunk.value(bag) }.to raise_error(RuntimeError) { |e| first = e }
      expect { thunk.value(bag) }.to raise_error(RuntimeError) { |e| second = e }

      expect(second).to be(first)
      expect(runs).to eq(1)
    end

    it "reports the memoized error through #error" do
      thunk = described_class.new(proc { |_p| raise ArgumentError, "nope" })

      expect { thunk.value(bag) }.to raise_error(ArgumentError)
      expect(thunk.error).to be_a(ArgumentError)
      expect(thunk.error.message).to eq("nope")
    end

    it "has no error before it is forced, and none after it succeeds" do
      thunk = described_class.new(proc { |_p| "fine" })

      expect(thunk.error).to be_nil
      thunk.value(bag)
      expect(thunk.error).to be_nil
    end

    # A ScriptError that escaped unrecorded would be re-run on the next read —
    # the double execution this mission exists to remove, arriving through the
    # least-expected door (an abstract method, a failed autoload).
    it "records a ScriptError the same way, so it is never reattempted either" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and raise NotImplementedError, "todo" })

      expect { thunk.value(bag) }.to raise_error(NotImplementedError)
      expect { thunk.value(bag) }.to raise_error(NotImplementedError)
      expect(runs).to eq(1)
      expect(thunk.error).to be_a(NotImplementedError)
    end

    # Process-level signals are not this object's business: catching them would
    # turn "the host is going down" into a memoized derivation result.
    it "lets a process-level exception through without recording it" do
      runs = 0
      thunk = described_class.new(proc { |_p| runs += 1 and raise Interrupt })

      expect { thunk.value(bag) }.to raise_error(Interrupt)
      expect(thunk.error).to be_nil
      expect { thunk.value(bag) }.to raise_error(Interrupt)
      expect(runs).to eq(2)
    end
  end
end
