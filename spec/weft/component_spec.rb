# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Component do
  describe "inherited hook and registry" do
    it "auto-registers subclasses with the global registry" do
      component_class = Class.new(Weft::Component) do
        def self.name = "AutoRegistered"
      end

      expect(Weft.registry.components).to include(component_class)
    end

    it "auto-registers grandchildren" do
      parent = Class.new(Weft::Component) do
        def self.name = "BaseComponent"
      end
      grandchild = Class.new(parent) do
        def self.name = "SpecificComponent"
      end

      expect(Weft.registry.components).to include(parent, grandchild)
    end

    it "registers abstract classes harmlessly" do
      abstract = Class.new(Weft::Component) do
        def self.name = "AbstractBase"
      end

      expect(Weft.registry.components).to include(abstract)
    end
  end

  describe ".render" do
    it "renders a component to an HTML string outside any DSL context" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Renderable"
        param :status

        def build(attributes = {})
          super
          div { text_node "status=#{params.status}" }
        end
      end

      html = component_class.render(status: "shipped")

      expect(html).to include("status=shipped")
      expect(html).to include("<div")
    end

    it "returns a bare fragment, not a full HTML document" do
      component_class = Class.new(Weft::Component) do
        def self.name = "SimpleRenderable"
      end

      html = component_class.render

      expect(html).not_to include("<!DOCTYPE")
      expect(html).not_to include("<html")
    end
  end

  describe "build" do
    it "resolves declared params from the context's wire params" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status
        param :count, default: 0

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}, count=#{params[:count]}" }
        end
      end

      html = Weft::Context.new({}, nil, wire_params: { "status" => "active", "count" => "5" }) do
        insert_tag(component_class)
      end.to_s

      expect(html).to include("status=active, count=5")
    end

    it "applies defaults for params missing from the wire" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}" }
        end
      end

      html = Weft::Context.new({}, nil) { insert_tag(component_class) }.to_s

      expect(html).to include("status=pending")
    end

    it "resolves wire params at any tree depth, not just the root" do
      child = Class.new(Weft::Component) do
        def self.name = "DepthChild"
        param :status

        def build(attributes = {})
          super
          text_node "child sees #{params.status}"
        end
      end
      parent = Class.new(Weft::Component) { def self.name = "DepthParent" }
      parent.define_method(:build) do |attributes = {}|
        super(attributes)
        insert_tag(child)
      end

      html = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) { insert_tag(parent) }.to_s

      expect(html).to include("child sees shipped")
    end

    it "makes params readable before super in a build body" do
      component_class = Class.new(Weft::Component) do
        def self.name = "EarlyReader"
        param :status

        def build(attributes = {})
          attributes[:class] = "pre-#{params.status}"
          super
        end
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "hot" }) { insert_tag(component_class) }

      expect(ctx.children.first.class_list).to include("pre-hot")
    end

    it "falls back to defaults when the context carries no wire source" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}" }
        end
      end

      html = Weft::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("status=pending")
    end

    it "routes a param-named builder kwarg to chrome, not the bag" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status, default: "pending"
      end

      ctx = Weft::Context.new({}, nil) { insert_tag(component_class, status: "shipped") }
      component = ctx.children.first

      expect(component.params.status).to eq("pending")
      expect(component.get_attribute(:status)).to eq("shipped")
    end

    # Once per call SITE rather than once per (class, key): the mistake belongs
    # to the line that wrote the kwarg, so two lines making it are two bugs and
    # keying by class alone would report only whichever rendered first. Still
    # bounded — a standing collision says its piece once, not once per render.
    it "warns once per call site, not once per render" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "CollideCard"
        param :title
      end

      2.times do
        Weft::Context.new({}, nil) do
          insert_tag(component_class, title: "a")
        end.to_s
      end

      expect(Weft.logger).to have_received(:warn).once.with(/title/)
    end

    it "warns for each distinct call site that collides" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "TwoSiteCard"
        param :title
      end

      Weft::Context.new({}, nil) do
        insert_tag(component_class, title: "a")
        insert_tag(component_class, title: "b")
      end.to_s

      expect(Weft.logger).to have_received(:warn).twice.with(/title/)
    end

    # `derives` and `defines` are the same mistake one door over: the value is
    # computed, so a call site cannot supply it either, and the kwarg silently
    # became chrome with nothing said about it.
    it "warns when the colliding key is a derivation rather than a param" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "DerivedCollideCard"
        derives(:tally) { |_p| 7 }
      end

      Weft::Context.new({}, nil) { insert_tag(component_class, tally: 3) }.to_s

      expect(Weft.logger).to have_received(:warn).once.with(/tally/)
    end

    it "names the way out — declaring the key as a hand-off" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "RemediableCard"
        param :status
      end

      Weft::Context.new({}, nil) { insert_tag(component_class, status: "shipped") }.to_s

      expect(Weft.logger).to have_received(:warn).with(/receives :status/)
    end

    it "sets the DOM id from weft_dom_id" do
      component_class = Class.new(Weft::Component) do
        def self.name = "StatCard"
        param :status
        identifies_by :status
      end

      ctx = Weft::Context.new({}, nil, wire_params: { "status" => "shipped" }) do
        insert_tag(component_class)
      end
      component = ctx.children.first

      expect(component.id).to eq("stat-card-shipped")
    end

    it "does not mutate the caller's attributes hash" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "NonMutating"
        param :status
      end

      shared = { status: "shipped", class: "big" }
      Weft::Context.new({}, nil) { insert_tag(component_class, **shared) }.to_s

      expect(shared).to eq(status: "shipped", class: "big")
    end

    it "renders as a div by default" do
      component_class = Class.new(Weft::Component) do
        def self.name = "SimpleCard"

        def build(attributes = {})
          super
          span "hello"
        end
      end

      html = Weft::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("<div")
      expect(html).to include("<span>hello</span>")
    end
  end

  describe "#despite_derivation_errors" do
    def render(klass) = Weft::Context.new { insert_tag(klass) }.to_s

    it "runs the block once and yields an empty hash when nothing has failed" do
      runs = 0
      klass = Class.new(Weft::Component) do
        def self.name = "CalmCard"
        derives(:fine) { |_p| "ok" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors do |errors|
          runs += 1
          span "errors=#{errors.size} fine=#{params.fine}"
        end
      end

      expect(render(klass)).to include("errors=0 fine=ok")
      expect(runs).to eq(1)
    end

    # The point of the helper: the block steps on a mine, and gets to run again
    # knowing where it is, without the adopter writing the loop.
    it "re-runs the block with the failure reported, so it can render around it" do
      klass = Class.new(Weft::Component) do
        def self.name = "MinedCard"
        derives(:safe) { |_p| "ok" }
        derives(:mine) { |_p| raise "mine exploded" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors do |errors|
          span "safe=#{params.safe}"
          span errors.key?(:mine) ? "mine unavailable: #{errors[:mine].message}" : "mine=#{params.mine}"
        end
      end

      html = render(klass)

      expect(html).to include("safe=ok")
      expect(html).to include("mine unavailable: mine exploded")
    end

    # Arbre appends children as they are created, so a naive retry stacks the
    # abandoned attempt on top of the next one.
    it "leaves no trace of the abandoned attempt" do
      klass = Class.new(Weft::Component) do
        def self.name = "NoTraceCard"
        derives(:mine) { |_p| raise "boom" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors do |errors|
          span "attempt"
          span params.mine unless errors.key?(:mine)
        end
      end

      expect(render(klass).scan("<span>attempt</span>").size).to eq(1)
    end

    # It rewinds only what the block emitted: whatever super and the build body
    # put in the tree before the block was entered has to survive.
    it "keeps what was rendered before the block" do
      klass = Class.new(Weft::Component) do
        def self.name = "PreambleCard"
        derives(:mine) { |_p| raise "boom" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        span "preamble"
        despite_derivation_errors do |errors|
          span params.mine unless errors.key?(:mine)
          span "body"
        end
      end

      html = render(klass)

      expect(html.scan("<span>preamble</span>").size).to eq(1)
      expect(html).to include("<span>body</span>")
    end

    # Real error components wrap their body in chrome, so the helper is used
    # inside an element block far more often than at the top of build. The
    # rewind has to take back what was emitted *there*, not the component's
    # own children.
    it "rewinds correctly when used inside a nested element" do # rubocop:disable RSpec/ExampleLength
      klass = Class.new(Weft::Component) do
        def self.name = "NestedCard"
        derives(:mine) { |_p| raise "boom" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        div(class: "wrapper") do
          span "chrome"
          despite_derivation_errors do |errors|
            span "attempt"
            span params.mine unless errors.key?(:mine)
          end
        end
      end

      html = render(klass)

      expect(html.scan("<span>chrome</span>").size).to eq(1)
      expect(html.scan("<span>attempt</span>").size).to eq(1)
    end

    it "finds every mine, however many the block steps on" do
      klass = Class.new(Weft::Component) do
        def self.name = "MinefieldCard"
        derives(:a) { |_p| raise "a" }
        derives(:b) { |_p| raise "b" }
        derives(:c) { |_p| raise "c" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors do |errors|
          %i[a b c].each { |k| span "#{k}=#{params.public_send(k)}" unless errors.key?(k) }
          span "found=#{errors.keys.sort.join(',')}"
        end
      end

      expect(render(klass)).to include("found=a,b,c")
    end

    # An ordinary bug in the block is not a derivation failure, and retrying it
    # would turn a typo into a confusing loop.
    it "re-raises an error that no derivation caused" do
      klass = Class.new(Weft::Component) do
        def self.name = "BuggyCard"
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors { |_errors| raise ArgumentError, "my own bug" }
      end

      expect { render(klass) }.to raise_error(ArgumentError, "my own bug")
    end

    # The rescue here has to cover whatever a Thunk records, or a failure it
    # remembered would escape the loop that exists to handle it.
    it "handles a ScriptError from a derivation, as the thunk records one" do
      klass = Class.new(Weft::Component) do
        def self.name = "AbstractDerivationCard"
        derives(:mine) { |_p| raise NotImplementedError, "todo" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors do |errors|
          span errors.key?(:mine) ? "mine unavailable" : "mine=#{params.mine}"
        end
      end

      expect(render(klass)).to include("mine unavailable")
    end

    it "re-raises a derivation failure the block never learns to avoid" do
      klass = Class.new(Weft::Component) do
        def self.name = "StubbornCard"
        derives(:mine) { |_p| raise "boom" }
      end
      klass.define_method(:build) do |attributes = {}|
        super(attributes)
        despite_derivation_errors { |_errors| span params.mine }
      end

      expect { render(klass) }.to raise_error(RuntimeError, "boom")
    end
  end
end
