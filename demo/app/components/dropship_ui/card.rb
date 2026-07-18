# frozen_string_literal: true

module DropshipUI
  # Visual primitive: a titled card with a body region. Used directly via
  # the `card` builder method for one-off cards, or subclassed (e.g.
  # `class Oms::RecentOrdersCard < DropshipUI::Card`) so a behavior-bearing
  # subclass becomes "a kind of card" structurally — one HTML wrapper, not
  # two.
  #
  # Direct callers hand title/link_text/link_href over; subclasses override
  # the readers to derive their own. Body children land in @body via the
  # add_child redirect.
  class Card < Weft::Component
    builder_method :card
    adds_children_to :@body

    receives :title, default: nil
    receives :link_text, default: nil
    receives :link_href, default: nil

    def build(attributes = {})
      super
      add_class "content-card"

      div(class: "content-card-header") do
        h2 card_title
        a(link_text, href: link_href, class: "text-decoration-none", style: "font-size:0.8rem") if link_text
      end

      @body = div(class: "content-card-body")
    end

    private

    # Prefixed to avoid shadowing the `title` tag builder.
    def card_title = params.title
    def link_text = params.link_text
    def link_href = params.link_href
  end
end
