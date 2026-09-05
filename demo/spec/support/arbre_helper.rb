# frozen_string_literal: true

# Test helper for rendering components in isolation.
#
# Everything here renders through Weft::Context, which is the context a
# request builds. A bare Arbre::Context is deliberately not offered: nothing
# in the app or the gem ever creates one, so a component tested in one is
# being exercised down a path no user reaches.
module ArbreHelper
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
