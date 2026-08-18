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

    it "falls back to defaults in a plain Arbre::Context (no wire source)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TestCard"
        param :status, default: "pending"

        def build(attributes = {})
          super
          div { text_node "status=#{params[:status]}" }
        end
      end

      html = Arbre::Context.new { insert_tag(component_class) }.to_s

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

    it "warns once per class and key when a param-named kwarg arrives" do
      allow(Weft.logger).to receive(:warn)
      component_class = Class.new(Weft::Component) do
        def self.name = "CollideCard"
        param :title
      end

      Weft::Context.new({}, nil) do
        insert_tag(component_class, title: "a")
        insert_tag(component_class, title: "b")
      end.to_s

      expect(Weft.logger).to have_received(:warn).once.with(/title/)
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

      html = Arbre::Context.new { insert_tag(component_class) }.to_s

      expect(html).to include("<div")
      expect(html).to include("<span>hello</span>")
    end
  end
end
