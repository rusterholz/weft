# frozen_string_literal: true

module DropshipUI
  # Visual primitive: a labeled stat with a big value and optional accent
  # color. label/value/accent are builder-method kwargs (extracted from
  # the attributes hash in build), not wire state — they describe how to
  # render, not what to remember across requests. Subclasses that DO want
  # wire state (e.g. Oms::OrderStatusCard's `param :status`) declare
  # it themselves and derive label/value/accent in their own build.
  class StatCard < Weft::Component
    builder_method :stat_card

    def build(attributes = {})
      @label = attributes.delete(:label)
      @value = attributes.delete(:value)
      @accent = attributes.delete(:accent)
      super
      add_class "stat-card"
      add_class "border-#{@accent}" if @accent

      div(class: "stat-label") { text_node @label.to_s }
      div(class: "stat-value") { text_node @value.to_s }
    end
  end
end
