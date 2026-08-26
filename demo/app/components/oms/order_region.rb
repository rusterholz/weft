# frozen_string_literal: true

module Oms
  # The order header region, in its two states: `OrderHeader` reading and
  # `EditableOrderHeader` editing. They hand the region back and forth with
  # `transfers`, and both answer to the same order — so the derivation lives
  # here rather than being written twice.
  #
  # That sharing is load-bearing, not just tidy. Whichever of the two renders
  # inherits the state its sibling composed, so one declaration is what makes
  # the hand-off agreement — rather than two components each holding a private
  # opinion about how the same order gets loaded.
  class OrderRegion < Weft::Component
    abstract!

    param :order_id, type: :uuid
    identifies_by :order_id

    derives(:order) { |p| Oms::Order.find(p.order_id) }
  end
end
