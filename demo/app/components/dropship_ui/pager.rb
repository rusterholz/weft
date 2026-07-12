# frozen_string_literal: true

module DropshipUI
  # Pagination widget for any panel that lists pageable records.
  # Renders offset text ("26–50 of 120") plus Prev / Page N of M / Next
  # buttons. The buttons use the demo's `:paginate` shorthand (registered
  # in config/shorthands.rb), which expands to htmx attrs that load the
  # caller's target_class into the target_id selector.
  #
  # Usage from a paneled component:
  #   pager(
  #     page_num: page_num, per_page: PER_PAGE, total: total,
  #     target_class: self.class, target_id: weft_id,
  #     target_page_class: OrdersPage,           # for push_url derivation
  #     extra_params: { status: attrs.status }   # preserved across pages
  #   )
  class Pager < Weft::Component
    builder_method :pager

    def build(attributes = {})
      @page_num = attributes.delete(:page_num) || 1
      @per_page = attributes.delete(:per_page) || 25
      @total = attributes.delete(:total) || 0
      @target_class = attributes.delete(:target_class)
      @target_id = attributes.delete(:target_id)
      @target_page_class = attributes.delete(:target_page_class)
      @extra_params = attributes.delete(:extra_params) || {}
      super

      return if @total.zero?

      add_class "d-flex justify-content-between align-items-center mt-2"
      set_attribute :style, "font-size:0.8rem"

      total_pages = [(@total.to_f / @per_page).ceil, 1].max
      offset_start = ((@page_num - 1) * @per_page) + 1
      offset_end = [@page_num * @per_page, @total].min

      div(class: "text-muted") { text_node "#{offset_start}–#{offset_end} of #{@total}" }

      div(class: "btn-group") do
        page_button("← Prev", target_page: @page_num - 1, disabled: @page_num <= 1)
        span(class: "btn btn-sm btn-outline-secondary disabled", style: "pointer-events:none") do
          text_node "Page #{@page_num} of #{total_pages}"
        end
        page_button("Next →", target_page: @page_num + 1, disabled: @page_num >= total_pages)
      end
    end

    private

    def page_button(label, target_page:, disabled:)
      classes = "btn btn-sm btn-outline-secondary"
      if disabled
        span(label, class: "#{classes} disabled", style: "pointer-events:none")
      else
        button label,
               paginate: @target_class,
               with: @extra_params.merge(page: target_page),
               target: "##{@target_id}",
               push_url: build_push_url(target_page),
               class: classes
      end
    end

    def build_push_url(target_page)
      base = @target_page_class.resolve_page_path
      params = @extra_params.merge(page: target_page)
      params.delete(:page) if target_page <= 1
      params = params.reject { |_, v| v.nil? || v == "" }
      params.empty? ? base : "#{base}?#{URI.encode_www_form(params)}"
    end
  end
end
