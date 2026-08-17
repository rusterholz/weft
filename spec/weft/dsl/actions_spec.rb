# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Actions do
  describe "performs DSL" do
    it "registers a named action with a callable" do
      component_class = Class.new(Weft::Component) do
        def self.name = "ActionTest"
        param :order_id
        performs(:advance) { nil }
      end

      action = component_class.actions[%i[advance post]]
      expect(action).to be_a(Weft::Action)
      expect(action.name).to eq(:advance)
      expect(action.method).to eq(:post)
      expect(action.renders).to eq(component_class)
    end

    it "registers a nameless action" do
      component_class = Class.new(Weft::Component) do
        def self.name = "RootAction"
        performs(method: :get) { nil }
      end

      action = component_class.actions[[nil, :get]]
      expect(action).not_to be_nil
      expect(action).to be_nameless
    end

    it "supports method:, swap:, and target: kwargs" do
      component_class = Class.new(Weft::Component) do
        def self.name = "CustomAction"
        performs(:remove, method: :delete, swap: :delete, target: "#parent") { nil }
      end

      action = component_class.actions[%i[remove delete]]
      expect(action.method).to eq(:delete)
      expect(action.swap).to eq(:delete)
    end

    it "looks up actions by name via action_for" do
      component_class = Class.new(Weft::Component) do
        def self.name = "LookupTest"
        performs(:advance) { nil }
        performs(:cancel, method: :delete) { nil }
      end

      expect(component_class.action_for(:advance).name).to eq(:advance)
      expect(component_class.action_for(:cancel).name).to eq(:cancel)
      expect(component_class.action_for(:nonexistent)).to be_nil
    end

    it "inherits actions from parent classes" do
      parent = Class.new(Weft::Component) do
        def self.name = "ParentAction"
        performs(:shared) { nil }
      end
      child = Class.new(parent) do
        def self.name = "ChildAction"
        performs(:own) { nil }
      end

      expect(child.action_for(:shared)).not_to be_nil
      expect(child.action_for(:own)).not_to be_nil
      expect(parent.action_for(:own)).to be_nil
    end
  end

  describe "dismisses DSL" do
    it "registers a performs action with swap: :delete" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Dismissable"
        dismisses(:close) { nil }
      end

      action = component_class.actions[%i[close delete]]
      expect(action).to be_a(Weft::Action)
      expect(action.swap).to eq(:delete)
      expect(action.method).to eq(:delete)
    end

    it "works without a block" do
      component_class = Class.new(Weft::Component) do
        def self.name = "SimpleDismiss"
        dismisses :remove
      end

      action = component_class.actions[%i[remove delete]]
      expect(action).not_to be_nil
      expect(action.callable).to be_nil
    end

    it "supports nameless form (DELETE at root path)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NamelessDismiss"
        dismisses
      end

      action = component_class.actions[[nil, :delete]]
      expect(action).not_to be_nil
      expect(action.swap).to eq(:delete)
    end

    it "forwards target: to the underlying action" do
      component_class = Class.new(Weft::Component) do
        def self.name = "TargetedDismiss"
        dismisses :remove, target: "closest tr"
      end

      action = component_class.actions[%i[remove delete]]
      expect(action.target).to eq("closest tr")
      expect(action.swap).to eq(:delete)
    end

    it "generates htmx delete attributes via action: kwarg" do
      component_class = Class.new(Weft::Component) do
        def self.name = "DismissRender"
        param :item_id
        dismisses :close

        def build(attributes = {})
          super
          button "X", action: :close
        end
      end

      html = component_class.render(item_id: "7")

      expect(html).to include('hx-delete="/_components/dismiss_render/close"')
      expect(html).to include('hx-swap="delete"')
    end
  end
end
