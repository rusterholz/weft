# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Identity do
  describe ".identifies_by" do
    it "records the declared identifiers in declaration order" do
      klass = Class.new(Weft::Component) do
        def self.name = "LineItemRow"
        param :order_id
        param :line_item_id
        identifies_by :order_id, :line_item_id
      end

      expect(klass.identifiers).to eq(%i[order_id line_item_id])
    end

    it "keeps the order given, not the order the params were declared in" do
      klass = Class.new(Weft::Component) do
        def self.name = "ReorderedRow"
        param :order_id
        param :line_item_id
        identifies_by :line_item_id, :order_id
      end

      expect(klass.identifiers).to eq(%i[line_item_id order_id])
    end

    it "declares no identifiers by default — the first param no longer identifies" do
      klass = Class.new(Weft::Component) do
        def self.name = "StatCard"
        param :status
      end

      expect(klass.identifiers).to eq([])
    end
  end

  describe "inheritance" do
    let(:base) do
      Class.new(Weft::Component) do
        def self.name = "IdentityBase"
        param :order_id
        param :customer_name
        identifies_by :order_id
      end
    end

    it "inherits the ancestor's identifiers when the subclass declares none" do
      child = Class.new(base) { def self.name = "IdentityChild" }

      expect(child.identifiers).to eq(%i[order_id])
    end

    it "replaces the ancestor's identifiers wholesale — never appends" do
      child = Class.new(base) do
        def self.name = "IdentityOverride"
        identifies_by :customer_name
      end

      expect(child.identifiers).to eq(%i[customer_name])
      expect(base.identifiers).to eq(%i[order_id])
    end

    it "lets a subclass identify by a param it could never demote positionally" do
      # The steel gate: `params` is superclass.params.merge(own_params), so an
      # inherited param always leads the hash and a subclass has no lever over
      # the old positional convention. A declaration is that lever.
      child = Class.new(base) do
        def self.name = "IdentityDemoter"
        param :own_key
        identifies_by :own_key
      end

      expect(child.params.keys.first).to eq(:order_id)
      expect(child.identifiers).to eq(%i[own_key])
    end
  end
end
