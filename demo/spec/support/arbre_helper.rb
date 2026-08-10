# frozen_string_literal: true

# Test helper for rendering Arbre components in isolation.
#
# This pattern will eventually become part of Weft's testing support.
# The idea: render a component in a minimal Arbre::Context, then assert
# on the HTML output, CSS classes, or content.
module ArbreHelper
  # Renders an Arbre block and returns the first top-level element.
  #
  #   component = render_arbre { stat_card label: "Orders", value: 42 }
  #   expect(component.to_s).to include("42")
  #
  def render_arbre(assigns = {}, &)
    Arbre::Context.new(assigns, nil, &).children.first
  end

  # Renders an Arbre block and returns the full HTML string.
  #
  #   html = render_arbre_html { status_badge "shipped" }
  #   expect(html).to include("badge-shipped")
  #
  def render_arbre_html(assigns = {}, &)
    Arbre::Context.new(assigns, nil, &).to_s
  end

  # Renders a Weft::Context block and returns the first top-level element.
  # Use for Weft::Components that need action:/trigger: expansion. Pass
  # `wire:` to simulate request params — components resolve their declared
  # params from it, exactly as they would from a query string.
  def render_weft(assigns = {}, wire: {}, &)
    Weft::Context.new(assigns, nil, wire_params: wire, &).children.first
  end

  # Renders a Weft::Context block and returns the full HTML string.
  def render_weft_html(assigns = {}, wire: {}, &)
    Weft::Context.new(assigns, nil, wire_params: wire, &).to_s
  end

  # Runs an action callable the way the Router does: against the state the
  # request composes from the wire, so the block reads the same params,
  # derivations and defines its component's `build` would.
  #
  #   run_action(Oms::OrderRow, :cancel, :delete, order_id: order.id)
  #
  def run_action(component_class, name, method = :post, **wire)
    action = component_class.actions[[name, method]]
    raise ArgumentError, "#{component_class}: no #{method.upcase} action #{name.inspect}" unless action

    Weft::DSL::Sandbox.run(
      Weft::Params::Assembly.for_request(component_class, wire.transform_keys(&:to_s)),
      &action.callable
    )
  end
end
