# frozen_string_literal: true

module DropshipUI
  # Pagination widget for any panel that lists pageable records.
  # Renders offset text ("26–50 of 120") plus Prev / Page N of M / Next
  # buttons. The buttons use the demo's `:paginate` preset (registered
  # in config/presets.rb), which expands to htmx attrs that load the
  # caller's target_class into the target_id selector.
  #
  # Usage from a paneled component:
  #   pager(
  #     page_num: page_num, per_page: PER_PAGE, total: total,
  #     target_class: self.class, target_id: weft_id,
  #     target_page_class: OrdersPage,           # for push_url derivation
  #     extra_params: { status: params.status }   # preserved across pages
  #   )
  class Pager < Weft::Component
    builder_method :pager

    receives :page_num, default: 1
    receives :per_page, default: 25
    receives :total, default: 0
    receives :target_class
    receives :target_id
    receives :target_page_class
    receives :extra_params, default: {}

    def build(attributes = {})
      super

      return if params.total.zero?

      add_class "d-flex justify-content-between align-items-center mt-2"
      set_attribute :style, "font-size:0.8rem"

      total_pages = [(params.total.to_f / params.per_page).ceil, 1].max
      offset_start = ((params.page_num - 1) * params.per_page) + 1
      offset_end = [params.page_num * params.per_page, params.total].min

      div(class: "text-muted") { text_node "#{offset_start}–#{offset_end} of #{params.total}" }

      div(class: "btn-group") do
        page_button("← Prev", target_page: params.page_num - 1, disabled: params.page_num <= 1)
        span(class: "btn btn-sm btn-outline-secondary disabled", style: "pointer-events:none") do
          text_node "Page #{params.page_num} of #{total_pages}"
        end
        page_button("Next →", target_page: params.page_num + 1, disabled: params.page_num >= total_pages)
      end
    end

    private

    def page_button(label, target_page:, disabled:)
      classes = "btn btn-sm btn-outline-secondary"
      if disabled
        span(label, class: "#{classes} disabled", style: "pointer-events:none")
      else
        button label,
               paginate: params.target_class,
               with: params.extra_params.merge(page: target_page),
               target: "##{params.target_id}",
               push_url: build_push_url(target_page),
               class: classes
      end
    end

    def build_push_url(target_page)
      base = params.target_page_class.resolve_page_path
      query = params.extra_params.merge(page: target_page)
      query.delete(:page) if target_page <= 1
      query = query.reject { |_, v| v.nil? || v == "" }
      query.empty? ? base : "#{base}?#{URI.encode_www_form(query)}"
    end
  end
end
