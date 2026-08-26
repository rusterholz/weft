# frozen_string_literal: true

module Drills
  # Every error drill is the same card: a title, a paragraph saying which
  # pathway it exercises, and then whatever demonstrates it. Subclasses
  # DropshipUI::Card so "a drill is a kind of card" is structural — one HTML
  # wrapper, not two — and the spacing every drill wanted stops being repeated
  # at ten call sites.
  #
  # Extracted when DrillsPage crossed its length limit: the honest answer to
  # ten copies of one shape is a component, not a bigger limit.
  class DrillCard < DropshipUI::Card
    builder_method :drill_card

    # Chrome: no route, no refresh, nothing brings it. An id it shares with
    # every sibling would be invalid HTML naming something nobody addresses.
    anonymous!

    receives :blurb

    def build(attributes = {})
      super
      add_class "mb-3"
      para params.blurb, class: "text-muted"
    end
  end
end
