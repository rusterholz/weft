# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Action do
  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "OrderHeader"
      param :order_id
    end
  end

  describe "initialization" do
    it "stores action metadata" do
      action = described_class.new(name: :advance, method: :post, renders: component_class)

      expect(action.name).to eq(:advance)
      expect(action.method).to eq(:post)
      expect(action.renders).to eq(component_class)
      expect(action.swap).to eq(:outer_html)
    end

    it "defaults method to :post" do
      action = described_class.new(name: :advance, renders: component_class)
      expect(action.method).to eq(:post)
    end

    it "defaults swap to :outer_html" do
      action = described_class.new(name: :advance, renders: component_class)
      expect(action.swap).to eq(:outer_html)
    end

    it "accepts custom swap and target" do
      action = described_class.new(name: :close, method: :delete, swap: :delete, renders: component_class)

      expect(action.swap).to eq(:delete)
      expect(action.method).to eq(:delete)
    end

    it "supports nameless actions" do
      action = described_class.new(name: nil, method: :get, renders: component_class)
      expect(action).to be_nameless
    end
  end

  describe "#route_path" do
    it "appends action name to the component path for named actions" do
      action = described_class.new(name: :advance, renders: component_class)
      expect(action.route_path("/_components/order_header")).to eq("/_components/order_header/advance")
    end

    it "uses the component path directly for nameless actions" do
      action = described_class.new(name: nil, method: :get, renders: component_class)
      expect(action.route_path("/_components/order_header")).to eq("/_components/order_header")
    end
  end

  describe "#to_htmx_attrs" do
    it "generates htmx attributes from component state" do
      action = described_class.new(name: :advance, method: :post, renders: component_class)
      klass = component_class

      ctx = Arbre::Context.new { insert_tag(klass, order_id: 42) }
      component = ctx.children.first

      htmx = action.to_htmx_attrs(component)

      expect(htmx["hx-post"]).to eq("/_components/order_header/advance")
      expect(htmx["hx-target"]).to eq("#order-header-42")
      expect(htmx["hx-swap"]).to eq("outerHTML")
      expect(htmx["hx-vals"]).to include('"order_id":42')
    end

    it "uses custom swap strategy" do
      action = described_class.new(name: :close, swap: :delete, renders: component_class)
      klass = component_class
      ctx = Arbre::Context.new { insert_tag(klass, order_id: 1) }

      htmx = action.to_htmx_attrs(ctx.children.first)
      expect(htmx["hx-swap"]).to eq("delete")
    end

    it "uses custom target selector" do
      action = described_class.new(name: :add, renders: component_class, target: "#items-list")
      klass = component_class
      ctx = Arbre::Context.new { insert_tag(klass, order_id: 1) }

      htmx = action.to_htmx_attrs(ctx.children.first)
      expect(htmx["hx-target"]).to eq("#items-list")
    end
  end
end
