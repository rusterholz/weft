# frozen_string_literal: true

module DropshipUI
  # Visual primitive: a titled card with a body region. Used directly via
  # the `card` builder method for one-off cards, or subclassed (e.g.
  # `class Oms::RecentOrdersCard < DropshipUI::Card`) so a behavior-bearing
  # subclass becomes "a kind of card" structurally — one HTML wrapper, not
  # two.
  #
  # Subclasses pass chrome params through `super` and add body children
  # directly; the @body container redirects them via add_child.
  class Card < Weft::Component
    builder_method :card
    adds_children_to :@body

    def build(attributes = {})
      card_title = attributes.delete(:title)
      link_text = attributes.delete(:link_text)
      link_href = attributes.delete(:link_href)
      super
      add_class "content-card"

      div(class: "content-card-header") do
        h2 card_title
        a(link_text, href: link_href, class: "text-decoration-none", style: "font-size:0.8rem") if link_text
      end

      @body = div(class: "content-card-body")
    end
  end
end
