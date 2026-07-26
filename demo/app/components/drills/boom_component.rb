# frozen_string_literal: true

module Drills
  # Always fails to build. Click-loaded from the drills page so the branded
  # error card swaps in exactly where the trigger was — proving one
  # component's failure never takes down the page around it. Retry re-fails
  # by design: this component has no working state to return to.
  class BoomComponent < Weft::Component
    # No params and no verbs, so routability isn't inferred — but the drill
    # trigger fetches this component at its own URL.
    routable!

    def build(attributes = {})
      super
      raise "the component drill exploded, as requested"
    end
  end
end
