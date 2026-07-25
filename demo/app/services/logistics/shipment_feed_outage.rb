# frozen_string_literal: true

require "fileutils"

module Logistics
  # Demo fault injection for the shipments live feed: while active, the
  # shipments lookup raises, so an open order page's SSE stream degrades
  # through the push-recovery path — countdown frames, then the close event,
  # then the resume affordance. Toggled from the OutageSwitch on the order
  # detail page.
  #
  # The flag is a file, not module state: dev-mode reloading rebuilds this
  # module on every request (config/environment.rb), so an ivar would reset
  # between the toggle action and the next stream cycle.
  module ShipmentFeedOutage
    class FeedUnavailable < StandardError
    end

    FLAG_PATH = File.join(APP_ROOT, "tmp", "shipment_feed_outage")

    class << self
      def active? = File.exist?(FLAG_PATH)

      def toggle!
        if active?
          File.delete(FLAG_PATH)
        else
          FileUtils.mkdir_p(File.dirname(FLAG_PATH))
          File.write(FLAG_PATH, "")
        end
      end

      def check!
        raise FeedUnavailable, "shipments feed is unavailable (simulated outage)" if active?
      end
    end
  end
end
