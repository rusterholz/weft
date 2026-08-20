# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Identity do
  def render_in_context(klass, wire_params: {})
    Weft::Context.new({}, nil, wire_params: wire_params) { insert_tag(klass) }.children.first
  end

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

    it "identifies by no param at all — a mint is not one" do
      # Two instances carrying the same mint are the same object to weft. That
      # is a property of the instance, not data the instance was handed.
      expect(badge.identifiers).to eq([])
    end

    it "keeps the mint out of the params surface entirely" do
      expect(badge.params).to be_empty
      expect(badge.declared_keys).to be_empty
    end

    it "leaves the params bag free of it at render time too" do
      instance = render_in_context(badge)

      expect(instance.params.to_h).to be_empty
      expect(instance.weft_mint).to match(/\AM\h{8}\z/)
    end

    it "reads the wire key when it is used, not when it was declared" do
      # Recording the name at declaration would strand already-loaded classes
      # on the old one the moment the knob moved.
      original = Weft.configuration.mint_key
      Weft.configuration.mint_key = :_weft_id

      expect(render_in_context(badge, wire_params: { "._weft_id" => "M1a2b3c4d" }).weft_dom_id).
        to eq("status-badge-M1a2b3c4d")
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

      expect(child).to be_unique
      expect(child.identifiers).to eq([])
      expect(parent.identifiers).to eq(%i[order_id])
    end

    it "is inherited by a subclass that declares no identity of its own" do
      child = Class.new(badge) { def self.name = "SpecialBadge" }

      expect(child).to be_unique
      expect(render_in_context(child).weft_dom_id).to match(/\Aspecial-badge-M\h{8}\z/)
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
      expect(render_in_context(child, wire_params: { "order_id" => "7" }).weft_mint).to be_nil
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

  describe "minting" do
    let(:badge) do
      Class.new(Weft::Component) do
        def self.name = "StatusBadge"
        unique!
        def build(attributes = {})
          super
          span "badge"
        end
      end
    end

    it "issues a token at first render, when the wire carries none" do
      expect(render_in_context(badge).weft_dom_id).to match(/\Astatus-badge-M\h{8}\z/)
    end

    it "issues a different token to each instance on the page" do
      ids = Array.new(5) { render_in_context(badge).weft_dom_id }

      expect(ids.uniq.size).to eq(5)
    end

    it "carries the token it was given, rather than issuing a new one" do
      instance = render_in_context(badge, wire_params: { "._mint" => "M1a2b3c4d" })

      expect(instance.weft_dom_id).to eq("status-badge-M1a2b3c4d")
    end

    it "serializes the token, so a refresh comes back to the same element" do
      # The whole point of a mint: issued once at first render, then carried
      # back and forth until something forces a new first render.
      instance = render_in_context(badge, wire_params: { "._mint" => "M1a2b3c4d" })

      expect(instance.weft_url).to include("._mint=M1a2b3c4d")
    end

    it "round-trips: the id a refresh resolves to is the id it was serving" do
      first = render_in_context(badge)
      carried = URI.decode_www_form(URI(first.weft_url).query).to_h

      expect(render_in_context(badge, wire_params: carried).weft_dom_id).to eq(first.weft_dom_id)
    end

    it "reissues rather than trusting a token that is not weft's" do
      # A mint arrives from the wire, where anything can be typed. An id
      # attribute is no place to put an unchecked string.
      instance = render_in_context(badge, wire_params: { "._mint" => '"><script>' })

      expect(instance.weft_dom_id).to match(/\Astatus-badge-M\h{8}\z/)
    end

    it "reissues a token of the wrong shape" do
      instance = render_in_context(badge, wire_params: { "._mint" => "M1a2b" })

      expect(instance.weft_dom_id).to match(/\Astatus-badge-M\h{8}\z/)
    end

    it "follows the configured key name" do
      original = Weft.configuration.mint_key
      Weft.configuration.mint_key = :_weft_id
      instance = render_in_context(badge, wire_params: { "._weft_id" => "M1a2b3c4d" })

      expect(instance.weft_dom_id).to eq("status-badge-M1a2b3c4d")
    ensure
      Weft.configuration.mint_key = original
    end

    it "gives a nested unique component its own token, never its parent's" do
      inner = badge
      outer = Class.new(Weft::Component) do
        def self.name = "BadgeHost"
        unique!
        define_method(:build) do |attributes = {}|
          super(attributes)
          insert_tag(inner)
          insert_tag(inner)
        end
      end

      host = render_in_context(outer)
      minted = host.children.map { |c| c.get_attribute("id") }.compact

      expect(minted.uniq.size).to eq(2)
      expect(minted).not_to include(host.weft_dom_id)
    end

    it "rides the component's own request lineage: refresh URL, stream, its actions" do
      acting = Class.new(Weft::Component) do
        def self.name = "ActingBadge"
        unique!
        performs(:advance) { nil }
      end
      instance = render_in_context(acting, wire_params: { "._mint" => "M1a2b3c4d" })
      action = Weft::Action.new(name: :advance, method: :post, renders: acting)

      expect(instance.weft_url).to include("._mint=M1a2b3c4d")
      expect(instance.send(:stream_url)).to include("._mint=M1a2b3c4d")
      expect(action.to_htmx_attrs(instance)["hx-vals"]).to include('"._mint":"M1a2b3c4d"')
      expect(action.to_htmx_attrs(instance)["hx-target"]).to eq("#acting-badge-M1a2b3c4d")
    end

    it "leaves a user's own param of the same name completely alone" do
      # The load-bearing isolation: weft's wire namespace is a leading dot the
      # operator can neither supply nor omit, so `param :_mint` is genuinely
      # the user's — it is not clobbered outbound nor read back inbound.
      clash = Class.new(Weft::Component) do
        def self.name = "Clash"
        unique!
        param :_mint
      end
      instance = render_in_context(clash, wire_params: { "._mint" => "M1a2b3c4d", "_mint" => "theirs" })

      expect(instance.params[:_mint]).to eq("theirs")
      expect(instance.weft_mint).to eq("M1a2b3c4d")
      expect(instance.weft_dom_id).to eq("clash-M1a2b3c4d")
      expect(instance.weft_url).to include("_mint=theirs").and include("._mint=M1a2b3c4d")
    end

    it "never rides someone else's request" do
      # `with:` defaults to the nearest component's params, which travel on an
      # element the user is wiring up — a different object's request. A mint
      # going along would assert that element IS this component, which is the
      # same falsehood `brings` refuses for a unique! companion.
      instance = render_in_context(badge, wire_params: { "._mint" => "M1a2b3c4d" })

      expect(instance.send(:serializable_params)).to be_empty
      expect(instance.weft_addressed_params).to eq("._mint" => "M1a2b3c4d")
    end

    it "does not mint for a component that never asked" do
      plain = Class.new(Weft::Component) do
        def self.name = "PlainCard"
        param :status
      end

      expect(render_in_context(plain).weft_dom_id).to eq("plain-card")
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
