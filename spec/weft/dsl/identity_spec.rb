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

  describe ".unique!" do
    let(:badge) do
      Class.new(Weft::Component) do
        def self.name = "StatusBadge"
        unique!
      end
    end

    it "marks the class as carrying a mint" do
      expect(badge).to be_unique
    end

    it "identifies by the mint key" do
      expect(badge.identifiers).to eq([:_mint])
    end

    it "declares the mint as a param, so it rides the wire back" do
      expect(badge.params).to have_key(:_mint)
    end

    it "marks the mint param internal, so it is weft's and not part of the surface" do
      expect(badge.params[:_mint][:internal]).to be(true)
    end

    it "reads the key name when it is used, not when it was declared" do
      # Recording the name at declaration would strand already-loaded classes
      # on the old one the moment the knob moved.
      original = Weft.configuration.mint_key
      Weft.configuration.mint_key = :_weft_id

      expect(badge.identifiers).to eq([:_weft_id])
      expect(badge.params).to have_key(:_weft_id)
      expect(badge.params).not_to have_key(:_mint)
    ensure
      Weft.configuration.mint_key = original
    end

    it "replaces an inherited identity wholesale, as identifies_by does" do
      parent = Class.new(Weft::Component) do
        def self.name = "KeyedParent"
        param :order_id
        identifies_by :order_id
      end
      child = Class.new(parent) do
        def self.name = "MintedChild"
        unique!
      end

      expect(child.identifiers).to eq([:_mint])
      expect(parent.identifiers).to eq(%i[order_id])
    end

    it "is inherited by a subclass that declares no identity of its own" do
      child = Class.new(badge) { def self.name = "SpecialBadge" }

      expect(child).to be_unique
      expect(child.identifiers).to eq([:_mint])
    end

    it "is overridden by a subclass declaring identifies_by" do
      child = Class.new(badge) do
        def self.name = "KeyedBadge"
        param :order_id
        identifies_by :order_id
      end

      expect(child).not_to be_unique
      expect(child.identifiers).to eq(%i[order_id])
      expect(child.params).not_to have_key(:_mint)
    end

    it "raises when a class body also declares identifies_by" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "Contradictory"
          param :order_id
          unique!
          identifies_by :order_id
        end
      end.to raise_error(Weft::InvalidDefinition, /unique!/)
    end

    it "raises in the other declaration order too" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "AlsoContradictory"
          param :order_id
          identifies_by :order_id
          unique!
        end
      end.to raise_error(Weft::InvalidDefinition, /unique!/)
    end

    it "reports not unique for a class that never declared it" do
      plain = Class.new(Weft::Component) { def self.name = "PlainCard" }

      expect(plain).not_to be_unique
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
