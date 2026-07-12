# frozen_string_literal: true

module DropshipUI
  class StatusBadge < Weft::Component
    builder_method :status_badge

    def build(status, attributes = {})
      super(attributes)
      add_class "badge badge-status badge-#{status.to_s.tr('_', '-')}"
      text_node status.to_s.tr("_", " ")
    end

    def tag_name
      "span"
    end
  end
end
