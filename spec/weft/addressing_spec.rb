# frozen_string_literal: true

require "arbre"

# Both address forms a component wears: its DOM id, its route path, its own
# URL, and whether it is addressable over HTTP at all.
RSpec.describe Weft::Addressing do
  describe "stem" do
    # A private extended method: reached through a throwaway host, as the
    # Component and Page derivations reach it.
    let(:host) { Class.new { extend Weft::Addressing } }

    it "strips the class-kind suffix" do
      expect(host.send(:stem, "Drills::BoomComponent", "Component")).to eq("Drills::Boom")
      expect(host.send(:stem, "DashboardPage", "Page")).to eq("Dashboard")
    end

    it "leaves a name that doesn't carry the suffix alone" do
      expect(host.send(:stem, "Oms::OrderHeader", "Component")).to eq("Oms::OrderHeader")
    end

    it "keeps the name whole when stripping would leave no usable stem" do
      expect(host.send(:stem, "DropshipUI::Component", "Component")).to eq("DropshipUI::Component")
      expect(host.send(:stem, "Component", "Component")).to eq("Component")
    end

    it "strips only a trailing suffix, never one embedded in the name" do
      expect(host.send(:stem, "ComponentPicker", "Component")).to eq("ComponentPicker")
    end

    it "is private — it is machinery, not surface" do
      expect { host.stem("Whatever", "Component") }.to raise_error(NoMethodError)
    end

    it "is reachable per-class through addressing_stem, which a custom path proc may call" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Drills::BoomComponent"
      end
      page_class = Class.new(Weft::Page) do
        def self.name = "Oms::DashboardPage"
      end

      expect(component_class.addressing_stem).to eq("Drills::Boom")
      expect(page_class.addressing_stem).to eq("Oms::Dashboard")
    end
  end

  describe ".mint" do
    it "issues a marked token" do
      expect(described_class.mint).to match(/\AM\h{8}\z/)
    end

    it "issues a different token every time — entropy, not a function of anything" do
      expect(Array.new(50) { described_class.mint }.uniq.size).to eq(50)
    end

    it "recognizes its own tokens and rejects everything else" do
      expect(described_class.mint?(described_class.mint)).to be(true)
      expect(described_class.mint?("M1a2b3c4d")).to be(true)
      expect(described_class.mint?("m1a2b3c4d")).to be(false)
      expect(described_class.mint?("M1a2b")).to be(false)
      expect(described_class.mint?("<script>")).to be(false)
      expect(described_class.mint?(nil)).to be(false)
    end

    it "cannot be confused with a digested token" do
      expect(described_class.mint?("D1a2b3c4d")).to be(false)
    end
  end

  describe "the DOM id and the route path agree on the stem" do
    it "strips a trailing Component from the id, as the path already does" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Drills::BoomComponent"
        param :row
      end

      expect(component_class.resolved_component_path).to eq("/_components/drills/boom")
      expect(component_class.weft_dom_id_for).to eq("drills-boom")
    end

    it "keeps the whole name in both when stripping would leave no usable stem" do
      component_class = Class.new(Weft::Component) do
        def self.name = "DropshipUI::Component"
        abstract!
      end

      expect(component_class.resolved_component_path).to eq("/_components/dropship_ui/component")
      expect(component_class.weft_dom_id_for).to eq("dropship-ui-component")
    end

    it "still refuses to route a routable class with no usable stem" do
      component_class = Class.new(Weft::Component) do
        def self.name = "MyApp::Component"
        param :anything
      end

      expect { component_class.resolved_component_path }.
        to raise_error(Weft::InvalidDefinition, /MyApp::Component/)
    end
  end

  describe "Page mirrors the stem rule" do
    it "keeps the whole name when stripping would leave no usable stem" do
      page_class = Class.new(Weft::Page) do
        def self.name = "DropshipUI::Page"
      end

      expect(page_class.send(:default_page_path)).to eq("/dropship_ui/page")
    end

    it "strips a trailing Page when a usable stem remains" do
      page_class = Class.new(Weft::Page) do
        def self.name = "Oms::DashboardPage"
      end

      expect(page_class.send(:default_page_path)).to eq("/oms/dashboard")
    end
  end

  describe "weft_dom_id" do
    it "composes the id from the declared identifiers, in declaration order" do
      component_class = Class.new(Weft::Component) do
        def self.name = "LineItemRow"
        param :order_id
        param :line_item_id
        identifies_by :order_id, :line_item_id
      end

      expect(component_class.weft_dom_id_for(order_id: 6, line_item_id: 3)).to eq("line-item-row-6-3")
    end

    it "reads identifiers by name, not by the argument hash order" do
      component_class = Class.new(Weft::Component) do
        def self.name = "OrderRow"
        param :order_id
        param :customer_name
        identifies_by :order_id
      end

      expect(component_class.weft_dom_id_for(customer_name: "Globex", order_id: 42)).to eq("order-row-42")
    end

    it "ignores params that are declared but not identifying" do
      component_class = Class.new(Weft::Component) do
        def self.name = "FilterPanel"
        param :status
        param :page
        identifies_by :status
      end

      expect(component_class.weft_dom_id_for(status: "shipped", page: 3)).to eq("filter-panel-shipped")
    end

    it "uses the class name alone when nothing identifies the component" do
      component_class = Class.new(Weft::Component) do
        def self.name = "GlobalStats"
        param :status
      end

      expect(component_class.weft_dom_id_for(status: "shipped")).to eq("global-stats")
    end

    it "handles namespaced class names" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Oms::OrderHeader"
        param :order_id
        identifies_by :order_id
      end

      expect(component_class.weft_dom_id_for(order_id: 42)).to eq("oms-order-header-42")
    end

    it "reads the identifiers off a built instance too" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StatCard"
        param :status
        identifies_by :status
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) do
        insert_tag(component_class)
      end

      expect(ctx.children.first.weft_dom_id).to eq("stat-card-shipped")
    end

    describe "A-prime composition" do
      let(:component_class) do
        Class.new(Weft::Component) do
          def self.name = "PersonCard"
          param :label
          identifies_by :label
        end
      end

      it "sanitizes an identifying value into the dash-free alphabet" do
        expect(component_class.weft_dom_id_for(label: "Alice Smith")).to eq("person-card-alice_smith")
      end

      it "converts dashes inside a value to underscores, so the separator stays unambiguous" do
        expect(component_class.weft_dom_id_for(label: "a-b")).to eq("person-card-a_b")
        expect(component_class.weft_dom_id_for(label: "ACME Corp--Ltd")).to eq("person-card-acme_corp_ltd")
      end

      it "strips punctuation a CSS selector could not carry" do
        expect(component_class.weft_dom_id_for(label: "O'Brien & Co.")).to eq("person-card-o_brien_co")
      end

      it "keeps the dashes of a uuid-typed value — they are fixed-shape, so nothing turns ambiguous" do
        uuid_class = Class.new(Weft::Component) do
          def self.name = "Oms::OrderHeader"
          param :order_id, type: :uuid
          identifies_by :order_id
        end

        expect(uuid_class.weft_dom_id_for(order_id: "f7c599ce-3945-4340-b4cc-5754a682ae43")).
          to eq("oms-order-header-f7c599ce-3945-4340-b4cc-5754a682ae43")
      end

      it "normalizes uuid case, since a UUID is case-insensitive" do
        uuid_class = Class.new(Weft::Component) do
          def self.name = "UpperCard"
          param :key, type: :uuid
          identifies_by :key
        end

        expect(uuid_class.weft_dom_id_for(key: "F7C599CE-3945-4340-B4CC-5754A682AE43")).
          to eq("upper-card-f7c599ce-3945-4340-b4cc-5754a682ae43")
      end

      it "falls back to dash-free rendering when a uuid-typed value isn't one" do
        # Self-correcting: the shape check, not the declaration, is what
        # guarantees a dash only ever appears inside a fixed-width segment.
        uuid_class = Class.new(Weft::Component) do
          def self.name = "LooseCard"
          param :key, type: :uuid
          identifies_by :key
        end

        expect(uuid_class.weft_dom_id_for(key: "not-a-uuid")).to eq("loose-card-not_a_uuid")
      end

      it "does not keep dashes for an untyped value that merely looks like a uuid" do
        expect(component_class.weft_dom_id_for(label: "f7c599ce-3945-4340-b4cc-5754a682ae43")).
          to eq("person-card-f7c599ce_3945_4340_b4cc_5754a682ae43")
      end

      it "renders every scalar kind, false included" do
        expect(component_class.weft_dom_id_for(label: 42)).to eq("person-card-42")
        expect(component_class.weft_dom_id_for(label: :hot)).to eq("person-card-hot")
        expect(component_class.weft_dom_id_for(label: true)).to eq("person-card-true")
        expect(component_class.weft_dom_id_for(label: false)).to eq("person-card-false")
      end
    end

    describe "digest mode" do
      let(:digested_class) do
        Class.new(Weft::Component) do
          def self.name = "PersonCard"
          param :label, digest: true
          identifies_by :label
        end
      end

      it "renders the slot as a marked token instead of the value" do
        expect(digested_class.weft_dom_id_for(label: "Alice Smith")).to eq("person-card-D5ed21b7f")
      end

      it "digests even a value that would have survived sanitization untouched" do
        # All-or-nothing: a per-value fallback would let a digested slot collide
        # with a literal value that is perfectly plausible for the same param.
        expect(digested_class.weft_dom_id_for(label: "alice")).to eq("person-card-D0a50500b")
      end

      it "marks the token with an uppercase prefix the sanitizer can never emit" do
        # parameterize downcases everything, exotic uppercase included, so a
        # literal value can never be mistaken for a generated token.
        segment = digested_class.weft_dom_id_for(label: "alice").split("-").last

        expect(segment).to start_with("D")
        expect(segment.length).to eq(9)
      end

      it "separates two values that sanitize to the same string" do
        # Digesting after sanitization would destroy exactly the distinction
        # digest exists to preserve.
        left = digested_class.weft_dom_id_for(label: "Al  green")
        right = digested_class.weft_dom_id_for(label: "al Green ")

        expect(left).not_to eq(right)
        expect("Al  green".parameterize).to eq("al Green ".parameterize)
      end

      it "separates nil from the empty string" do
        # Reading `to_s` would render both as "", collapsing them to one token.
        expect(digested_class.weft_dom_id_for(label: nil)).to eq("person-card-D5da3a4c7")
        expect(digested_class.weft_dom_id_for(label: "")).to eq("person-card-D12ae32cb")
      end

      it "separates a value from its own string rendering" do
        expect(digested_class.weft_dom_id_for(label: 42)).
          not_to eq(digested_class.weft_dom_id_for(label: "42"))
      end

      it "digests a blank value rather than leaving the slot empty" do
        expect(digested_class.weft_dom_id_for(label: nil)).not_to end_with("-")
        expect(digested_class.weft_dom_id_for({})).to eq("person-card-D5da3a4c7")
      end

      it "is stable across processes" do
        # String#hash is seeded per process: it would agree with itself under
        # one worker and disagree under two.
        id = digested_class.weft_dom_id_for(label: "Alice Smith")
        out = `#{RbConfig.ruby} -Ilib -rweft -e '#{<<~SCRIPT.strip}'`
          klass = Class.new(Weft::Component) do
            def self.name = "PersonCard"
            param :label, digest: true
            identifies_by :label
          end
          print klass.weft_dom_id_for(label: "Alice Smith")
        SCRIPT

        expect(out).to eq(id)
        expect(out).to match(/-D\h{8}\z/)
      end

      it "widens the token when the declaration asks for a length" do
        wide = Class.new(Weft::Component) do
          def self.name = "WideCard"
          param :label, digest: 16
          identifies_by :label
        end

        expect(wide.weft_dom_id_for(label: "alice")).to eq("wide-card-D0a50500b2a3435fe")
      end

      it "follows the gem-wide length when the declaration only sets the flag" do
        original = Weft.configuration.digest_length
        Weft.configuration.digest_length = 4
        expect(digested_class.weft_dom_id_for(label: "alice")).to eq("person-card-D0a50")
      ensure
        Weft.configuration.digest_length = original
      end

      it "lets a per-param length override the gem-wide one" do
        original = Weft.configuration.digest_length
        Weft.configuration.digest_length = 4
        wide = Class.new(Weft::Component) do
          def self.name = "WideCard"
          param :label, digest: 16
          identifies_by :label
        end

        expect(wide.weft_dom_id_for(label: "alice")).to eq("wide-card-D0a50500b2a3435fe")
      ensure
        Weft.configuration.digest_length = original
      end

      it "digests only the params that asked for it" do
        mixed = Class.new(Weft::Component) do
          def self.name = "MixedCard"
          param :kind
          param :label, digest: true
          identifies_by :kind, :label
        end

        expect(mixed.weft_dom_id_for(kind: "vip", label: "alice")).to eq("mixed-card-vip-D0a50500b")
      end

      it "gives repeated identical values the same token, since nothing salts them" do
        pair = Class.new(Weft::Component) do
          def self.name = "PairCard"
          param :left, digest: true
          param :right, digest: true
          identifies_by :left, :right
        end

        expect(pair.weft_dom_id_for(left: nil, right: nil)).to eq("pair-card-D5da3a4c7-D5da3a4c7")
      end

      it "takes precedence over uuid rendering" do
        uuid = Class.new(Weft::Component) do
          def self.name = "UuidCard"
          param :key, type: :uuid, digest: true
          identifies_by :key
        end

        expect(uuid.weft_dom_id_for(key: "f7c599ce-3945-4340-b4cc-5754a682ae43")).
          to eq("uuid-card-Dcad6c957")
      end
    end

    describe "blank slots" do
      before { allow(Weft.logger).to receive(:warn) }

      let(:pair_class) do
        Class.new(Weft::Component) do
          def self.name = "PairRow"
          param :left
          param :right
          identifies_by :left, :right
        end
      end

      it "keeps a slot for every declared identifier, so positions never collapse" do
        expect(pair_class.weft_dom_id_for(left: nil, right: 3)).to eq("pair-row--3")
        expect(pair_class.weft_dom_id_for(left: 3, right: nil)).to eq("pair-row-3-")
      end

      it "leaves both slots empty when neither value is there" do
        expect(pair_class.weft_dom_id_for(left: nil, right: nil)).to eq("pair-row--")
      end

      it "treats a value that sanitizes away as blank" do
        expect(pair_class.weft_dom_id_for(left: "---", right: 3)).to eq("pair-row--3")
      end

      it "warns, naming the id the blank values share and the declaration that fixes it" do
        pair_class.weft_dom_id_for(left: nil, right: 3)

        expect(Weft.logger).to have_received(:warn).
          with(/PairRow identifies by :left.*"pair-row--3".*digest: true/m)
      end

      it "warns for each blank identifier, not just the first" do
        pair_class.weft_dom_id_for(left: nil, right: nil)

        expect(Weft.logger).to have_received(:warn).with(/:left/).once
        expect(Weft.logger).to have_received(:warn).with(/:right/).once
      end

      it "warns once per param however many instances render" do
        # A hundred-row table would otherwise say the same thing a hundred times.
        100.times { |i| pair_class.weft_dom_id_for(left: nil, right: i) }

        expect(Weft.logger).to have_received(:warn).once
      end

      it "stays quiet when every identifying value is there" do
        pair_class.weft_dom_id_for(left: 1, right: 2)

        expect(Weft.logger).not_to have_received(:warn)
      end

      it "stays quiet in digest mode, where a blank value still gets its own slot" do
        digested = Class.new(Weft::Component) do
          def self.name = "DigestedPair"
          param :left, digest: true
          param :right, digest: true
          identifies_by :left, :right
        end

        digested.weft_dom_id_for(left: nil, right: nil)

        expect(Weft.logger).not_to have_received(:warn)
      end

      it "stays quiet for a component that identifies by nothing" do
        bare = Class.new(Weft::Component) do
          def self.name = "GlobalStats"
          param :status
        end

        bare.weft_dom_id_for({})

        expect(Weft.logger).not_to have_received(:warn)
      end

      it "suffixes a single blank identifier rather than dropping to the bare base" do
        # Reverses M14, deliberately: a bare base id let two blank-keyed
        # siblings collide, and since M17 a collision drops a companion.
        single = Class.new(Weft::Component) do
          def self.name = "ContactResults"
          param :q
          identifies_by :q
        end

        expect(single.weft_dom_id_for(q: nil)).to eq("contact-results-")
        expect(single.weft_dom_id_for(q: "")).to eq("contact-results-")
        expect(single.weft_dom_id_for({})).to eq("contact-results-")
      end
    end
  end

  describe "resolved_component_path" do
    it "derives path from class name using the default component_path proc" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StatCard"
      end

      expect(component_class.resolved_component_path).to eq("/_components/stat_card")
    end

    it "auto-derives namespace from module nesting" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Oms::OrderHeader"
      end

      expect(component_class.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "strips a trailing 'Component' suffix from the class name" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Oms::OrderHeaderComponent"
      end

      expect(component_class.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "uses class-level component_path string override" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StatCard"
        self.component_path = "/custom/stats"
      end

      expect(component_class.resolved_component_path).to eq("/custom/stats")
    end

    it "uses class-level component_path proc override" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Oms::OrderHeader"
        self.component_path = ->(klass) { "/api/#{klass.name.split('::').last.downcase}" }
      end

      expect(component_class.resolved_component_path).to eq("/api/orderheader")
    end

    it "inherits component_path proc from parent and resolves with child class" do
      parent = Class.new(Weft::Component) do
        def self.name = "Oms::Base"
        self.component_path = lambda { |klass|
          component_name = klass.name.split("::").last.underscore
          "/_components/oms/#{component_name}"
        }
      end
      child = Class.new(parent) do
        def self.name = "Oms::OrderHeader"
      end

      expect(child.resolved_component_path).to eq("/_components/oms/order_header")
    end

    it "raises a helpful error for a routable class whose name has no usable stem" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Foo::Component"
        param :id
      end

      expect { component_class.resolved_component_path }.
        to raise_error(Weft::InvalidDefinition, /routable but named for its kind.*abstract!/m)
    end

    it "does not guard a non-routable class with an empty stem (it never routes)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Foo::Component"
      end

      expect { component_class.resolved_component_path }.not_to raise_error
    end
  end

  describe ".routable?" do
    it "is routable when attributes are declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "WithAttrs"
        param :status
      end

      expect(component_class).to be_routable
    end

    it "is routable when actions are declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "WithAction"
        performs(:go) { nil }
      end

      expect(component_class).to be_routable
    end

    it "is routable when refresh triggers are declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "WithRefresh"
        refreshes every: 10
      end

      expect(component_class).to be_routable
    end

    it "is routable when push config is declared" do
      component_class = Class.new(Weft::Component) do
        def self.name = "WithPush"
        pushes every: 5
      end

      expect(component_class).to be_routable
    end

    it "is not routable when bare (no params, verbs, or declarations)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "BareComponent"
      end

      expect(component_class).not_to be_routable
    end

    it "is not routable with only announces (response modifier, not addressable)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "OnlyTriggers"
        announces "some-event"
      end

      expect(component_class).not_to be_routable
    end

    it "is not routable with only brings (response modifier, not addressable)" do
      target = Class.new(Weft::Component) { def self.name = "IncTarget2" }
      component_class = Class.new(Weft::Component) do
        def self.name = "OnlyIncludes"
      end
      component_class.brings(target)

      expect(component_class).not_to be_routable
    end

    it "is routable when parent is routable (inherits attributes)" do
      parent = Class.new(Weft::Component) do
        def self.name = "RoutableParent"
        param :id
      end
      child = Class.new(parent) do
        def self.name = "ChildOfRoutable"
      end

      expect(child).to be_routable
    end

    describe "unique! and routability" do
      it "does not publish an endpoint for a component whose only param is weft's own" do
        # Weft adding a param on your behalf is no reason for a public GET to
        # appear — the routability lint exists to prevent exactly that.
        badge = Class.new(Weft::Component) do
          def self.name = "StatusBadge"
          unique!
        end

        expect(badge).not_to be_routable
      end

      it "still routes when something the user declared earns it" do
        actor = Class.new(Weft::Component) do
          def self.name = "ActingBadge"
          unique!
          performs(:advance) { nil }
        end

        expect(actor).to be_routable
      end

      it "still routes when the user declares a param of their own" do
        keyed = Class.new(Weft::Component) do
          def self.name = "KeyedBadge"
          unique!
          param :status
        end

        expect(keyed).to be_routable
      end

      it "routes when asked explicitly" do
        forced = Class.new(Weft::Component) do
          def self.name = "ForcedBadge"
          unique!
          routable!
        end

        expect(forced).to be_routable
      end
    end

    describe "abstract! and routable! overrides" do
      it "abstract! makes a routable class non-routable" do
        component_class = Class.new(Weft::Component) do
          def self.name = "AbstractedComponent"
          param :id
          abstract!
        end

        expect(component_class).not_to be_routable
      end

      it "abstract! does not percolate — concrete subclass is routable again" do
        parent = Class.new(Weft::Component) do
          def self.name = "AbstractParent"
          param :id
          abstract!
        end
        child = Class.new(parent) do
          def self.name = "ConcreteChild"
        end

        expect(parent).not_to be_routable
        expect(child).to be_routable
      end

      it "routable! forces routability when inference says no" do
        component_class = Class.new(Weft::Component) do
          def self.name = "ForcedRoutable"
          routable!
        end

        expect(component_class).to be_routable
      end

      it "dependent! makes a routable class non-routable, like abstract!" do
        component_class = Class.new(Weft::Component) do
          def self.name = "LeafComponent"
          param :highlight
          receives :order
          dependent!
        end

        expect(component_class).not_to be_routable
      end

      it "routable! does not percolate to subclasses" do
        parent = Class.new(Weft::Component) do
          def self.name = "ForcedParent"
          routable!
        end
        child = Class.new(parent) do
          def self.name = "BareChild"
        end

        expect(parent).to be_routable
        expect(child).not_to be_routable
      end
    end
  end

  describe "#weft_url" do
    it "returns the component path with current params" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped", "page" => 2 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?status=shipped&page=2")
    end

    it "overrides specific params" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped", "page" => 2 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url(page: 3)).to eq("/_components/panel?status=shipped&page=3")
    end

    it "omits nil values from the URL" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Panel"
        param :status
        param :page, default: 1
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "page" => 1 }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.weft_url).to eq("/_components/panel?page=1")
    end
  end
end
