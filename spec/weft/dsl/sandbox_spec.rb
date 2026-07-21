# frozen_string_literal: true

RSpec.describe Weft::DSL::Sandbox do
  # The `self` a verb block runs against: a fresh, disposable "void context"
  # created per execution. Blocks are (params) -> value pure functions — the
  # arguments and the return value are explicit, constants resolve lexically,
  # Kernel stays reachable, and nothing component-specific is in reach.

  it "passes the argument to the block and returns its value" do
    expect(described_class.run(41) { |n| n + 1 }).to eq(42)
  end

  it "passes multiple arguments through, as recovery blocks want (params, error)" do
    expect(described_class.run(:params, :err) { |p, e| [p, e] }).to eq(%i[params err])
  end

  it "keeps Kernel reachable" do
    expect(described_class.run("42") { |s| Integer(s) }).to eq(42)
  end

  it "raises NameError on a bare method call — no component or class state in reach" do
    expect { described_class.run(nil) { some_component_method } }.to raise_error(NameError, /some_component_method/)
  end

  it "allows scratch instance variables within one execution" do
    expect(described_class.run(nil) { @scratch = 7 }).to eq(7)
  end

  it "gives each execution a fresh instance, so scratch never leaks between blocks" do
    described_class.run(nil) { @leak = "set" }
    expect(described_class.run(nil) { instance_variable_defined?(:@leak) }).to be(false)
  end
end
