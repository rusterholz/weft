# frozen_string_literal: true

module Oms
  # The order header region, in its two states: `OrderHeader` reading and
  # `EditableOrderHeader` editing. They hand the region back and forth with
  # `transfers`, and both answer to the same order — so the derivation lives
  # here rather than being written twice.
  #
  # That sharing is load-bearing, not just tidy. Whichever of the two renders
  # inherits the state its sibling composed, and a component whose own
  # derivation is shadowed by a *different* one upstream gets a warning about
  # it. One declaration means the hand-off is agreement.
  class OrderRegion < Weft::Component
    abstract!

    param :order_id, type: :string

    derives(:order) { |p| Oms::Order.find(p.order_id) }
  end
end
