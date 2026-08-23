# frozen_string_literal: true

module DropshipUI
  class StatusBadge < Weft::Component
    builder_method :status_badge

    # The status arrives as a build argument, not a param, so there is nothing
    # here to identify by — and a page lists many badges. `unique!` hands each
    # one its own slot instead of letting them all wear the class id.
    unique!

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
