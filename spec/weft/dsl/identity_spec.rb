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

  describe "the block form" do
    let(:carted) do
      Class.new(Weft::Component) do
        def self.name = "CartPanel"
        param :user_id
        identifies_by { |params| "cart-#{params.user_id}" }
      end
    end

    it "returns the whole id, not a slot in one" do
      expect(carted.weft_dom_id_for(user_id: 7)).to eq("cart-7")
    end

    it "bypasses the stem, the separator and the sanitizer alike" do
      loud = Class.new(Weft::Component) do
        def self.name = "LoudPanel"
        identifies_by { |_params| "Shouting_ID" }
      end

      expect(loud.weft_dom_id_for({})).to eq("Shouting_ID")
    end

    it "runs against params, with no reach into the instance" do
      # The sandbox contract: verb blocks are (params) -> value pure functions
      # with a void self, so a block stays portable to any process.
      probing = Class.new(Weft::Component) do
        def self.name = "ProbingPanel"
        identifies_by { |_params| self.class.name.split("::").last }
      end

      expect(probing.weft_dom_id_for({})).to eq("Sandbox")
    end

    it "sees the complete bag, not just what serializes" do
      # The block runs at the same branch point build would see, so a value
      # this component derives is as reachable as one that came off the wire.
      derived = Class.new(Weft::Component) do
        def self.name = "DerivedPanel"
        param :order_id
        derives(:slug) { |params| "order-#{params.order_id}" }
        identifies_by { |params| "panel-#{params.slug}" }
      end

      instance = render_in_context(derived, wire_params: { "order_id" => "9" })

      expect(instance.weft_dom_id).to eq("panel-order-9")
    end

    it "is honored on the class path too, where there is no instance to ask" do
      # This is the hole it closes: a `weft_dom_id` override is instance-only,
      # so error recovery gave a component a different id than a normal render.
      expect(carted.weft_dom_id_for(user_id: 3)).to eq("cart-3")
    end

    it "does not fall back when the block raises" do
      # Landing nowhere beats landing somewhere wrong: the convention it
      # overrode would answer with a different id, putting the fragment on some
      # other component's element.
      broken = Class.new(Weft::Component) do
        def self.name = "BrokenPanel"
        identifies_by { |_params| raise "no id for you" }
      end

      expect { broken.weft_dom_id_for({}) }.to raise_error(RuntimeError, /no id for you/)
    end

    it "permits collisions — deliberate ones are the reason it exists" do
      twinned = Class.new(Weft::Component) do
        def self.name = "TwinnedPanel"
        param :whatever
        identifies_by { |_params| "always-the-same" }
      end

      expect(twinned.weft_dom_id_for(whatever: 1)).to eq("always-the-same")
      expect(twinned.weft_dom_id_for(whatever: 2)).to eq("always-the-same")
    end

    it "raises when the block returns something no selector could carry" do
      # Collisions are permitted; malformed ids are not. An id weft cannot
      # target with `#id` is broken for htmx, not merely unconventional.
      ["has spaces", "#hash", ".dot", "", "9leading-digit", nil, 42].each do |bad|
        klass = Class.new(Weft::Component) do
          def self.name = "BadIdPanel"
          identifies_by { |_params| bad }
        end

        expect { klass.weft_dom_id_for({}) }.
          to raise_error(Weft::InvalidDefinition, /BadIdPanel/), "expected #{bad.inspect} to be refused"
      end
    end

    it "exposes the block so the registry can skip its load-time id check" do
      expect(carted.identity_block).to be_a(Proc)
      expect(Class.new(Weft::Component) { def self.name = "Plain" }.identity_block).to be_nil
    end

    it "refuses both forms at once" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "DoubleFormed"
          param :order_id
          identifies_by(:order_id) { |params| params.order_id.to_s }
        end
      end.to raise_error(Weft::InvalidDefinition, /both/)
    end

    it "refuses a bare declaration with neither names nor block" do
      # Behaviorally identical to omitting it, so it is a comment pretending to
      # be code — and the likely real case is someone who meant to list params.
      expect do
        Class.new(Weft::Component) do
          def self.name = "EmptyDeclaration"
          identifies_by
        end
      end.to raise_error(Weft::InvalidDefinition, /identifies_by/)
    end

    it "is inherited, and replaceable wholesale by either other form" do
      child = Class.new(carted) { def self.name = "SubCart" }
      keyed = Class.new(carted) do
        def self.name = "KeyedCart"
        identifies_by :user_id
      end

      expect(child.weft_dom_id_for(user_id: 4)).to eq("cart-4")
      expect(keyed.weft_dom_id_for(user_id: 4)).to eq("keyed-cart-4")
      expect(keyed.identity_block).to be_nil
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

      expect(instance.weft_component_url).to include("._mint=M1a2b3c4d")
    end

    it "round-trips: the id a refresh resolves to is the id it was serving" do
      first = render_in_context(badge)
      carried = URI.decode_www_form(URI(first.weft_component_url).query).to_h

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

      expect(instance.weft_component_url).to include("._mint=M1a2b3c4d")
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
      expect(instance.weft_component_url).to include("_mint=theirs").and include("._mint=M1a2b3c4d")
    end

    it "never rides someone else's request" do
      # `with:` defaults to the nearest component's params, which travel on an
      # element the user is wiring up — a different object's request. A mint
      # going along would assert that element IS this component, which is the
      # same falsehood `brings` refuses for a unique! companion.
      instance = render_in_context(badge, wire_params: { "._mint" => "M1a2b3c4d" })

      expect(instance.send(:serializable_params)).to be_empty
      expect(instance.weft_addressing_params).to eq("._mint" => "M1a2b3c4d")
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
