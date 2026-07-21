# frozen_string_literal: true

module DropshipUI
  # Visual primitive: a labeled stat with a big value and optional accent
  # color. Direct `stat_card(label:, value:, accent:)` callers hand the
  # values over; subclasses that derive them instead (e.g.
  # Oms::OrderStatusCard from its `status` param) declare `derives` for
  # the same keys — the bag doesn't care which door filled it.
  class StatCard < Weft::Component
    builder_method :stat_card

    receives :label, default: nil
    receives :value, default: nil
    receives :accent, default: nil

    def build(attributes = {})
      super
      add_class "stat-card"
      add_class "border-#{params.accent}" if params.accent

      div(class: "stat-label") { text_node params.label.to_s }
      div(class: "stat-value") { text_node params.value.to_s }
    end
  end
end
