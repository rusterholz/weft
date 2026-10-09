# frozen_string_literal: true

# Component specs render through the public `Component.render` and
# `Component.render_element`; what's left here runs a verb block on its own.
module ArbreHelper
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
