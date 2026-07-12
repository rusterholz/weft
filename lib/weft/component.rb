# frozen_string_literal: true

require "uri"
require "weft/context/interception"

module Weft
  # Base class for all Weft components. Extends Arbre::Component with:
  # - Attribute DSL for declaring wire state
  # - Convention-based DOM ID and partial URL
  # - Auto-registration with the global Registry
  class Component < Arbre::Component
    extend Weft::Registry::Eligibility

    include Weft::DSL::Attributes
    include Weft::DSL::Recoveries
    include Weft::DSL::Triggers
    include Weft::DSL::Inclusions
    include Weft::DSL::Updates
    include Weft::DSL::Actions
    include Weft::DSL::Containers

    class << self
      # Class-level path override (string or proc). Inherited by subclasses.
      def component_path
        if instance_variable_defined?(:@component_path)
          @component_path
        elsif superclass.respond_to?(:component_path)
          superclass.component_path
        end
      end

      attr_writer :component_path

      # Resolves the actual path string for this component class. An explicit
      # class-level override (string or proc) wins; otherwise the configured
      # default proc derives one from the class name (see default_component_path).
      def resolved_component_path
        case (path = component_path)
        when Proc then path.call(self)
        when String then path
        else default_component_path
        end
      end

      # Inferred routability from declared state, ignoring any explicit
      # override (see Weft::Registry::Eligibility#routable?). A component is
      # independently addressable when it declares interactive behavior —
      # attributes, actions, refresh triggers, or push config. Pure
      # presentational components (none of those) register but are never served.
      # Subclasses fall back to this when they have no override of their own, so
      # an abstract parent does not disable concrete children.
      def inferred_routable?
        attributes.any? || actions.any? || refresh_triggers.any? || !push_config.nil?
      end

      def inherited(subclass)
        super
        Weft.registry.register(subclass)
      end

      # Render this component as an HTML string, outside any Arbre DSL context.
      # Used by the Router for partial responses, and available to users for
      # testing, REPL exploration, or any standalone rendering need.
      #
      #   StatCard.render(status: "shipped")  # => "<div id=\"...\">...</div>"
      def render(**attributes)
        klass = self
        Weft::Context.new({}, nil) do
          insert_tag(klass, **attributes)
        end.to_s
      end

      # Compute the would-be DOM ID for an instance of this class given a
      # plain attrs hash, without instantiating. The Router uses this to
      # populate the `:component_id` auto-injected attribute when a recovery
      # target opts in. Single source of truth; the instance method delegates.
      def weft_id_for(attrs = {})
        base = name.underscore.tr("/", "-").tr("_", "-")
        primary_value = attrs.respond_to?(:values) ? attrs.values.first : nil
        primary_value ? "#{base}-#{primary_value}" : base
      end

      private

      # Gem-default name-based path derivation, plus the well-formedness guard.
      # Mirrors {Weft::Page.default_page_path}: a routable class whose demodulized
      # name has no usable stem (e.g. a bare +Component+ or +Foo::Component+)
      # can't form a sensible default route, so we raise with remediation
      # guidance rather than emit a degenerate "/_components/". Non-routable
      # classes never reach a route and are exempt.
      def default_component_path
        if routable? && name.to_s.demodulize.delete_suffix("Component").empty?
          raise Weft::InvalidDefinition,
                "#{name.inspect} has no resolvable default component path. " \
                "Either rename the class with a meaningful stem (e.g. OrdersPanel), " \
                "set self.component_path = \"/your/path\" explicitly, " \
                "or mark the class abstract! if it isn't meant to route."
        end

        Weft.configuration.component_path.call(self)
      end
    end

    include Weft::Context::Interception

    # Gem-default recovery edges. Symbol form defers resolution until error-handling
    # time so reassigning the matching Weft.configuration knob propagates everywhere.
    # NotFound is declared first (more specific) so a component-context 404 renders
    # the not-found body; StandardError stays last as the catch-all.
    recovers from: Weft::NotFound, with: :not_found_component
    recovers from: StandardError, with: :error_component

    def build(attributes = {})
      schema = self.class.attributes
      @attrs = Weft::Attributes.extract_from(attributes, using: schema)
      super(attributes.except(*schema.keys))
      self.id = weft_id
      apply_refresh_attrs
      apply_push_attrs
    end

    # URL to this component's Weft route with current attrs as query params.
    # Pass overrides to change specific attr values in the URL.
    #
    #   weft_url                          # => "/_components/orders_panel?status=shipped&page=1"
    #   weft_url(page: 2)                 # => "/_components/orders_panel?status=shipped&page=2"
    #   weft_url(status: nil, page: 1)    # => "/_components/orders_panel?page=1"
    def weft_url(**overrides)
      path = self.class.resolved_component_path
      params = @attrs.to_h.merge(overrides).compact
      params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
    end

    # Convention-based DOM ID: dasherized class name + primary attribute value.
    def weft_id
      self.class.weft_id_for(@attrs ? @attrs.to_h : {})
    end

    private

    # URL to this component's Weft route with current attrs (no overrides).
    # Used internally by apply_refresh_attrs.
    def refresh_url
      weft_url
    end

    def apply_refresh_attrs
      triggers = self.class.refresh_triggers
      return if triggers.empty?

      set_attribute "hx-get", refresh_url
      set_attribute "hx-trigger", triggers.join(", ")
      set_attribute "hx-swap", "outerHTML"
    end

    # Apply SSE connection attributes for components declaring `pushes`.
    # Uses innerHTML swap — the wrapper element (holding the SSE connection)
    # must persist across pushes.
    def apply_push_attrs
      config = self.class.push_config
      return unless config&.key?(:every)

      set_attribute "hx-ext", "sse"
      set_attribute "sse-connect", stream_url
      set_attribute "sse-swap", weft_id
      set_attribute "hx-swap", "innerHTML"
    end

    # URL to this component's SSE stream endpoint with current attrs.
    def stream_url
      path = "#{self.class.resolved_component_path}/#{Weft.configuration.stream_suffix}"
      params = @attrs.to_h.compact
      params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
    end
  end
end
