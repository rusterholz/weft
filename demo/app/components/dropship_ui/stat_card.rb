# frozen_string_literal: true

module DropshipUI
  # Visual primitive: a labeled stat with a big value and optional accent
  # color. Direct `stat_card(label:, value:, accent:)` callers hand the
  # values over; subclasses that derive them instead (e.g.
  # Oms::OrderStatusCard from its `status` param) override the readers and
  # take no hand-off at all.
  class StatCard < Weft::Component
    builder_method :stat_card

    receives :label, default: nil
    receives :value, default: nil
    receives :accent, default: nil

    def build(attributes = {})
      super
      add_class "stat-card"
      add_class "border-#{stat_accent}" if stat_accent

      div(class: "stat-label") { text_node stat_label.to_s }
      div(class: "stat-value") { text_node stat_value.to_s }
    end

    private

    # Prefixed to avoid shadowing the `label` tag builder.
    def stat_label = params.label
    def stat_value = params.value
    def stat_accent = params.accent
  end
end
