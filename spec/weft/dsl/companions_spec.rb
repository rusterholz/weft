# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Companions do
  describe "bringing a unique! component" do
    it "raises, since a companion cannot be addressed by a token it has never seen" do
      # unique! buys in-page uniqueness and self-refresh stability. It cannot
      # make a component addressable from someone ELSE's request: the companion
      # resolves from the host's params, which have never heard of the token,
      # so it mints a fresh one and the swap targets an id not on the page.
      badge = Class.new(Weft::Component) do
        def self.name = "MintedBadge"
        unique!
      end

      expect do
        Class.new(Weft::Component) do
          def self.name = "BadgeHost"
          param :order_id
          brings badge
        end
      end.to raise_error(Weft::InvalidDefinition, /unique!/)
    end
  end

  describe "brings DSL" do
    it "stores companions with component class" do
      included = Class.new(Weft::Component) { def self.name = "IncTarget" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncSource"
      end
      component_class.brings(included)

      expect(component_class.companions.size).to eq(1)
      expect(component_class.companions.first[:component_class]).to eq(included)
    end

    it "stores an on: filter, normalized to an array" do
      included = Class.new(Weft::Component) { def self.name = "IncFiltered" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncFilterSource"
      end
      component_class.brings(included, on: :advance)

      expect(component_class.companions.first[:on]).to eq([:advance])
    end

    it "accepts an array of action names for on:" do
      included = Class.new(Weft::Component) { def self.name = "IncMultiOn" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncMultiOnSource"
      end
      component_class.brings(included, on: %i[advance retreat])

      expect(component_class.companions.first[:on]).to eq(%i[advance retreat])
    end

    it "stores a when: filter, normalized to an array" do
      included = Class.new(Weft::Component) { def self.name = "IncWhen" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncWhenSource"
      end
      component_class.brings(included, when: :transferred)

      expect(component_class.companions.first[:when]).to eq([:transferred])
    end

    it "rejects an unknown when: value at declaration" do
      included = Class.new(Weft::Component) { def self.name = "IncBadWhen" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncBadWhenSource"
      end

      expect { component_class.brings(included, when: :pushed) }.
        to raise_error(Weft::InvalidDefinition, /:transferred/)
    end

    it "rejects unknown keywords" do
      included = Class.new(Weft::Component) { def self.name = "IncBadKw" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncBadKwSource"
      end

      expect { component_class.brings(included, whenn: :transferred) }.
        to raise_error(ArgumentError, /whenn/)
    end

    it "stores optional block for attr mapping" do
      included = Class.new(Weft::Component) { def self.name = "IncMapped" }
      component_class = Class.new(Weft::Component) do
        def self.name = "IncMapSource"
      end
      component_class.brings(included) { |params| { id: params[:order_id] } }

      expect(component_class.companions.first[:block]).to be_a(Proc)
    end

    it "inherits companions from parent classes" do
      included = Class.new(Weft::Component) { def self.name = "InheritedInc" }
      parent = Class.new(Weft::Component) do
        def self.name = "IncParent"
      end
      parent.brings(included)
      child = Class.new(parent) do
        def self.name = "IncChild"
      end

      expect(child.companions.size).to eq(1)
      expect(parent.companions.size).to eq(1)
    end

    it "accumulates multiple companions" do
      inc_a = Class.new(Weft::Component) { def self.name = "IncA" }
      inc_b = Class.new(Weft::Component) { def self.name = "IncB" }
      component_class = Class.new(Weft::Component) do
        def self.name = "MultiInc"
      end
      component_class.brings(inc_a)
      component_class.brings(inc_b)

      expect(component_class.companions.size).to eq(2)
    end
  end
end
