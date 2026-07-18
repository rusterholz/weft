# frozen_string_literal: true

require "weft/context/interception"

module Weft
  # Arbre::Context subclass that intercepts element creation to expand
  # Weft kwargs into htmx attributes.
  #
  # Works at every nesting depth because Arbre instance_evals the top-level
  # block, making the Context the receiver for all insert_tag calls throughout
  # the element tree.
  #
  # Supported kwargs:
  # - `action: :name` — expands into htmx attrs for a declared performs/transfers action
  # - `navigate: { key: val }` — expands into htmx GET to self with overridden attrs
  # - `trigger: "event"` — sets hx-trigger (standalone or alongside action:/navigate:)
  class Context < Arbre::Context
    include Interception

    # The render's wire params (query/body/path values), carried on the
    # context so every component in the tree resolves its own declared
    # params at any depth. Assigned before super because Arbre's initialize
    # instance_evals the construction block — the tree builds during super.
    attr_reader :wire_params

    def initialize(assigns = {}, helpers = nil, wire_params: nil, &)
      @wire_params = wire_params || {}
      super(assigns, helpers, &)
    end

    # @api private
    # One-shot register for `receives` hand-offs. Interception stages the
    # extracted kwargs here immediately before Arbre constructs the target
    # (insert_tag → build_tag → new); the new instance consumes them during
    # params assembly. Class-checked so a stale staging can never leak into
    # a different component's bag.
    def stage_received(klass, values)
      @staged_received = [klass, values]
    end

    # @api private
    def take_received!(klass)
      staged_class, values = @staged_received
      return unless staged_class.equal?(klass)

      @staged_received = nil
      values
    end

    # @api private
    # Expands Weft kwargs into htmx attributes. Invoked by the Interception
    # mixin's #insert_tag on the root Weft::Context (via +arbre_context+).
    def expand_weft_attrs(attrs, for_class: nil)
      attrs = attrs.dup
      custom_trigger = attrs.delete(:trigger)
      push_url = attrs.delete(:push_url)
      attrs = expand_action(attrs, for_class: for_class) || expand_navigate(attrs) || expand_loads(attrs) ||
              expand_preset(attrs) || attrs
      attrs["hx-trigger"] = resolve_trigger(custom_trigger) if custom_trigger
      attrs["hx-push-url"] = push_url.to_s if push_url
      attrs
    end

    # @api private
    # Guard check for whether an attrs hash carries any Weft kwarg. Invoked by
    # the Interception mixin's #insert_tag on the root Weft::Context (via
    # +arbre_context+).
    def weft_kwarg?(hash)
      hash[:action].is_a?(Symbol) || hash.key?(:trigger) || hash[:navigate].is_a?(Hash) ||
        hash[:loads].is_a?(Class) || hash.key?(:push_url) || find_preset_kwarg(hash)
    end

    private

    def expand_action(attrs, for_class: nil)
      action_name = attrs[:action]
      return unless action_name.is_a?(Symbol)

      component = find_action_context(action_name)
      return unless component

      action = component.class.action_for(action_name)
      htmx = action.to_htmx_attrs(component)
      expanded = attrs.except(:action).merge(htmx)
      return augment_for_form(expanded, action, htmx) if for_class && for_class <= Arbre::HTML::Form

      expanded
    end

    # On <form> elements, also emit the HTML action and method attributes so
    # non-JS submission works (browser POSTs to the same URL htmx would).
    # Drop hx-vals because the form fields are the submission payload —
    # hx-vals would duplicate or shadow them.
    def augment_for_form(expanded, action, htmx)
      url = htmx["hx-#{action.method}"]
      expanded.except("hx-vals").merge("action" => url, "method" => action.method.to_s)
    end

    def expand_navigate(attrs)
      overrides = attrs[:navigate]
      return unless overrides.is_a?(Hash)

      component = find_nearest_component
      return unless component

      attrs.except(:navigate).merge(navigate_attrs(component, overrides))
    end

    def expand_loads(attrs)
      target_class = attrs[:loads]
      return unless target_class.is_a?(Class)

      validate_loads_kwargs!(attrs)
      remaining = attrs.except(:loads, :swap, :target, :with)
      remaining.merge(loads_attrs(target_class, resolve_with(attrs), attrs[:swap], attrs[:target]))
    end

    def expand_preset(attrs)
      preset_key, target_class = find_preset_kwarg(attrs)
      return unless preset_key

      build_preset_attrs(attrs, preset_key, target_class, Weft.preset(preset_key))
    end

    # A preset value is either a target Class (derive the URL from it) or a
    # ready-made URL String (retry-style — the caller already has the URL).
    def find_preset_kwarg(attrs)
      attrs.find { |k, v| (v.is_a?(Class) || v.is_a?(String)) && Weft.preset(k) }
    end

    def build_preset_attrs(attrs, preset_key, target_or_url, preset)
      target = attrs[:target] || preset[:target]
      raise ArgumentError, "#{preset_key}: requires target: (e.g., target: :self)" unless target

      swap = attrs[:swap] || preset[:swap]
      htmx = if target_or_url.is_a?(String)
               htmx_get_attrs(target_or_url, swap, target)
             else
               loads_attrs(target_or_url, resolve_with(attrs), swap, target)
             end
      htmx["hx-trigger"] = resolve_trigger(preset[:trigger]) if preset[:trigger]
      attrs.except(preset_key, :swap, :target, :with).merge(htmx)
    end

    def resolve_with(attrs)
      attrs[:with] || find_nearest_component&.serializable_params || {}
    end

    def validate_loads_kwargs!(attrs)
      raise ArgumentError, "loads: requires swap: (e.g., swap: :fill)" unless attrs[:swap]
      raise ArgumentError, "loads: requires target: (e.g., target: :self)" unless attrs[:target]
    end

    def find_action_context(action_name)
      el = current_arbre_element
      while el
        return el if el.is_a?(Weft::Component) && el.class.action_for(action_name)

        el = el.parent
      end
      nil
    end

    def find_nearest_component
      el = current_arbre_element
      while el
        return el if el.is_a?(Weft::Component)

        el = el.parent
      end
      nil
    end

    def navigate_attrs(component, overrides)
      {
        "hx-get" => component.weft_url(**overrides),
        "hx-target" => "##{component.weft_id}",
        "hx-swap" => "outerHTML"
      }
    end

    def loads_attrs(target_class, with_attrs, swap, target)
      htmx_get_attrs(component_url(target_class, with_attrs), swap, target)
    end

    def component_url(target_class, with_attrs)
      path = target_class.resolved_component_path
      params = with_attrs.compact
      params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
    end

    def htmx_get_attrs(url, swap, target)
      {
        "hx-get" => url,
        "hx-swap" => Action.resolve_swap(swap),
        "hx-target" => resolve_target(target)
      }
    end

    def resolve_target(target)
      case target
      when :self then "this"
      when String then target
      else
        # Arbre element reference — extract #id
        target.respond_to?(:id) ? "##{target.id}" : target.to_s
      end
    end

    def resolve_trigger(value)
      Action.resolve_trigger(value)
    end
  end
end
