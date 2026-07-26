# frozen_string_literal: true

module Drills
  # Always fails, and recovers by transferring to a page: the recovers chain
  # answers the htmx fetch with HX-Redirect, so triggering this drill
  # navigates to the dashboard instead of swapping in a fragment.
  class RedirectBoomComponent < Weft::Component
    # See BoomComponent: fetched at its own URL, so routability is explicit.
    routable!

    class Failure < StandardError
    end

    recovers from: Failure, with: DashboardPage

    def build(attributes = {})
      super
      raise Failure, "the redirect drill exploded, as requested"
    end
  end
end
