# frozen_string_literal: true

# Named constants (not anonymous) so insert_tag resolves them across the Arbre
# 1.7 / 2.2 matrix. The tree built is: Outer > Middle(<div class="middle-body">) >
# Leaf. Middle carries a role module. Each node stashes itself as it builds.
module M7Fixtures
  NODES = {} # rubocop:disable Style/MutableConstant
  module Paginatable; end

  class Outer < Weft::Component
    def self.name = "M7Fixtures::Outer"

    def build(attributes = {})
      super
      NODES[:outer] = self
      insert_tag M7Fixtures::Middle
    end
  end

  class Middle < Weft::Component
    include Paginatable

    def self.name = "M7Fixtures::Middle"

    def build(attributes = {})
      super
      NODES[:middle] = self
      div(class: "middle-body") { insert_tag M7Fixtures::Leaf }
    end
  end

  class Leaf < Weft::Component
    def self.name = "M7Fixtures::Leaf"

    def build(attributes = {})
      super
      NODES[:leaf] = self
    end
  end
end

RSpec.describe Weft::Traversal do
  let(:nodes) do
    M7Fixtures::NODES.clear
    Weft::Context.new { insert_tag M7Fixtures::Outer }
    M7Fixtures::NODES
  end
  let(:leaf) { nodes[:leaf] }
  let(:middle) { nodes[:middle] }
  let(:outer) { nodes[:outer] }

  describe "#closest" do
    it "includes self by default (self is the nearest node)" do
      expect(leaf.closest(Weft::Component)).to be(leaf)
      expect(leaf.closest(M7Fixtures::Leaf)).to be(leaf)
    end

    it "matches by class, is_a?-style (a specific ancestor type)" do
      expect(leaf.closest(M7Fixtures::Outer)).to be(outer)
    end

    it "matches by module/role" do
      expect(leaf.closest(M7Fixtures::Paginatable)).to be(middle)
    end

    it "matches by Symbol tag name, self included" do
      expect(leaf.closest(:div)).to be(leaf) # the component's own wrapper is a <div>
    end

    it "returns nil when nothing matches" do
      expect(leaf.closest(:section)).to be_nil
    end

    it "honors include_self: false" do
      expect(leaf.closest(Weft::Component, include_self: false)).to be(middle)
    end

    it "refines with an optional block — positional AND block must match" do
      # nearest Weft::Component that is the outer one: leaf and middle match the
      # positional but not the block, so the walk climbs past them.
      found = leaf.closest(Weft::Component) { |c| c.equal?(outer) }
      expect(found).to be(outer)
    end
  end

  describe "#enclosing" do
    it "excludes self and returns the nearest matching ancestor" do
      expect(leaf.enclosing(Weft::Component)).to be(middle)
    end

    it "reaches a specific ancestor type above the nearest" do
      expect(leaf.enclosing(M7Fixtures::Outer)).to be(outer)
    end

    it "returns nil with no matching ancestor" do
      expect(leaf.enclosing(M7Fixtures::Leaf)).to be_nil
    end

    it "skips self for a tag match, returning the ancestor element" do
      div = leaf.enclosing(:div)
      expect(div).not_to be(leaf)
      expect(div.tag_name).to eq("div")
      expect(div.class_list).to include("middle-body")
    end
  end

  describe "bang forms" do
    it "closest! returns the match when present" do
      expect(leaf.closest!(Weft::Component)).to be(leaf)
    end

    it "closest! raises Weft::AncestorNotFound when nothing matches" do
      expect { leaf.closest!(M7Fixtures::Leaf, include_self: false) }.to raise_error(Weft::AncestorNotFound, /M7Fixtures::Leaf/)
    end

    it "enclosing! raises when no matching ancestor" do
      expect { leaf.enclosing!(:section) }.to raise_error(Weft::AncestorNotFound)
    end
  end

  describe "matcher validation" do
    it "rejects a String matcher (no CSS-selector matching)" do
      expect { leaf.closest("div") }.to raise_error(ArgumentError, /Class, Module, or Symbol/)
    end
  end
end
