# frozen_string_literal: true

module DropshipUI
  class StatusBadge < Weft::Component
    builder_method :status_badge

    receives :status

    # A table lists many badges, and many of them share a status, so the
    # status can't tell instances apart. `unique!` hands each one its own
    # slot instead of letting them all wear the class id.
    unique!

    def build(attributes = {})
      super
      add_class "badge badge-status badge-#{params.status.to_s.tr('_', '-')}"
      text_node params.status.to_s.tr("_", " ")
    end

    def tag_name
      "span"
    end
  end
end
