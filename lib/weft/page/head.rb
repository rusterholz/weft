# frozen_string_literal: true

require "arbre"

require "weft/dsl/sandbox"
require "weft/error"
require "weft/params"

module Weft
  class Page < Arbre::Component
    # The document-head surface: the `title` verb (class-level DSL, override
    # semantics — nearest declaration in the ancestry wins) and the head
    # assembly that consumes it. Mixed into Weft::Page alongside Assets,
    # whose render_assets this module's build_head drives.
    module Head
      def self.included(base) = base.extend(ClassMethods)

      module ClassMethods
        # Declare the page's <title>. A static value, or a block computed from
        # the page's params at render time — a `(params) → value` function run
        # in the verb sandbox, like every other verb block.
        #
        #   title "Orders"
        #   title { |params| "Order ##{params.order_id}" }
        #
        # The nearest declaration in the class ancestry wins; without one
        # anywhere, the title falls back to "Weft".
        def title(value = nil, &block)
          if value && block
            raise Weft::InvalidDefinition, "#{name}: title takes a value or a block, not both"
          elsif value.nil? && block.nil?
            raise Weft::InvalidDefinition, "#{name}: title needs a value or a block"
          end

          @title_declaration = block || value
        end

        # The declared title (own or nearest inherited); nil when no ancestor declares.
        def title_declaration
          if instance_variable_defined?(:@title_declaration)
            @title_declaration
          elsif superclass.respond_to?(:title_declaration)
            superclass.title_declaration
          end
        end
      end

      private

      def build_head
        insert_tag(Arbre::HTML::Head) do
          meta charset: "utf-8"
          meta name: "viewport", content: "width=device-width, initial-scale=1"
          title { text_node resolved_page_title }
          render_assets
          render_htmx_config
        end
      end

      # The page's <title> text: the declared title (static, or block-computed
      # from params in the verb sandbox), else "Weft".
      def resolved_page_title
        case (declared = self.class.title_declaration)
        when Proc then Weft::DSL::Sandbox.run(@params || Weft::Params.new({}), &declared)
        when nil then "Weft"
        else declared
        end
      end

      def render_htmx_config
        script do
          text_node htmx_config_js.html_safe
        end
      end

      def htmx_config_js
        <<~JS
          htmx.config.responseHandling = [
            {code: "204", swap: false},
            {code: "[23]..", swap: true},
            {code: "[45]..", swap: true, error: true}
          ];
        JS
      end
    end
  end
end
