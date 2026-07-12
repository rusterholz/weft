# frozen_string_literal: true

RSpec.describe Weft::DSL::Containers do
  let(:container_class) do
    Class.new(Weft::Component) do
      def self.name = "MacroContainer"

      adds_children_to :@body

      def build(attributes = {})
        super
        h2 "Header" # structural; @body not yet set, goes to wrapper
        @body = div(class: "body-region")
      end
    end
  end

  describe ".adds_children_to" do
    it "redirects user-block children into the declared ivar after build" do
      klass = container_class
      html = Weft::Context.new({}, nil) do
        insert_tag(klass) { span "block content" }
      end.to_s

      # span should appear inside body-region, not directly under the wrapper.
      expect(html).to match(%r{<div class="body-region">\s*<span>block content</span>\s*</div>})
    end

    it "lets structural children added during build pass through to the wrapper" do
      klass = container_class
      html = Weft::Context.new({}, nil) { insert_tag(klass) }.to_s

      # h2 is structural — added before @body is assigned, ends up outside body-region
      expect(html).to match(%r{<h2>Header</h2>\s*<div class="body-region">})
    end

    it "rejects a symbol that does not start with @" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "BadIvar"
          adds_children_to :body
        end
      end.to raise_error(Weft::InvalidDefinition, /must start with @/)
    end

    it "rejects a non-Symbol argument" do
      expect do
        Class.new(Weft::Component) do
          def self.name = "NonSymbolIvar"
          adds_children_to "@body"
        end
      end.to raise_error(ArgumentError, /expects a Symbol/)
    end

    it "raises a clear error when build returned without ever assigning the ivar" do
      bad = Class.new(Weft::Component) do
        def self.name = "ForgotIvar"

        adds_children_to :@body

        def build(attributes = {})
          super
          # Oops — never assigned @body.
        end
      end

      expect do
        Weft::Context.new({}, nil) { insert_tag(bad) { span "x" } }.to_s
      end.to raise_error(Weft::MissingContainerIvar,
                         /declared `adds_children_to :@body` but never assigned @body in build/)
    end

    it "works on Weft::Page subclasses too (mixed in by default)" do
      klass = Class.new(Weft::Page) do
        def self.name = "ContainerPage"
        adds_children_to :@main

        def build(attributes = {})
          super
          @main = div(class: "page-main")
        end
      end

      html = Weft::Context.new({}, nil) do
        insert_tag(klass) { span "page-body" }
      end.to_s

      expect(html).to match(%r{<div class="page-main">\s*<span>page-body</span>\s*</div>})
    end
  end
end
