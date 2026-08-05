# frozen_string_literal: true

# One card per error-recovery pathway, each with a live trigger — the page
# that proves the app's branded error handling end-to-end. Failing drills are
# linked or click-loaded, never embedded, so this page always renders cleanly.
class DrillsPage < ApplicationPage
  self.page_path = "/drills"

  title "Error drills"

  # Every recovery pathway the app can demonstrate, in the order they appear.
  # A new pathway earns a name here and a matching render_<name>_drill method —
  # which is the whole of what "new pathways get a card as they ship" costs.
  DRILLS = %i[missing_record routing_miss validation component_failure destructive_swap
              page_failure redirect_recovery companion_failure stream_outage].freeze

  def build(attributes = {})
    super
    div(class: "page-header") { h1 "Error drills" }
    DRILLS.each { |drill| send(:"render_#{drill}_drill") }
  end

  private

  def current_path = "/drills"
  def drill_button = "btn btn-sm btn-outline-secondary"

  def render_missing_record_drill
    card(title: "Branded 404 — missing record", class: "mb-3") do
      para "Detail pages use bare ActiveRecord lookups; one recovers declaration maps " \
           "RecordNotFound to the branded not-found page with a genuine 404.", class: "text-muted"
      div(class: "d-flex gap-2") do
        a "Missing order", href: "/orders/no-such-order", class: drill_button
        a "Missing shipment", href: "/shipments/no-such-shipment", class: drill_button
        a "Missing driver", href: "/drivers/no-such-driver", class: drill_button
      end
    end
  end

  def render_routing_miss_drill
    card(title: "Branded 404 — routing miss", class: "mb-3") do
      para "No route, no page: the router's not-found chain renders the branded page.",
           class: "text-muted"
      a "Visit an unrouted path", href: "/no-such-path", class: drill_button
    end
  end

  def render_validation_drill
    card(title: "Validation failure (422)", class: "mb-3") do
      para "Submit the order form with no items selected — it recovers in place, " \
           "keeping your input and showing the message.", class: "text-muted"
      a "Open the order form", href: "/orders/new", class: drill_button
    end
  end

  def render_component_failure_drill
    card(title: "Component failure (500)", class: "mb-3") do
      para "Click-loads a component whose build always raises: the branded error card " \
           "swaps in where the button was, and the rest of this page is untouched. " \
           "Retry re-fails, on purpose.", class: "text-muted"
      button "Trigger component failure", load_more: Drills::BoomComponent, class: drill_button
    end
  end

  def render_destructive_swap_drill
    card(title: "Destructive-swap failure", class: "mb-3") do
      para "Each row's delete always fails server-side: the error swaps in as a real " \
           "table row where the deleted one would have vanished — the rest of the " \
           "table is untouched.", class: "text-muted"
      table(class: "table table-data mb-0") do
        tbody do
          boom_row row: "one", label: "Doomed row one"
          boom_row row: "two", label: "Doomed row two"
        end
      end
    end
  end

  def render_page_failure_drill
    card(title: "Page failure (500)", class: "mb-3") do
      para "A full-document render that raises: the branded error page takes over.",
           class: "text-muted"
      a "Explode a full page", href: "/drills/boom", class: drill_button
    end
  end

  def render_redirect_recovery_drill
    card(title: "Redirect recovery", class: "mb-3") do
      para "This component recovers from its failure by transferring to a page: htmx " \
           "follows the HX-Redirect and you land on the dashboard.", class: "text-muted"
      button "Trigger redirect recovery", load_more: Drills::RedirectBoomComponent,
                                          class: drill_button
    end
  end

  def render_companion_failure_drill
    card(title: "Companion failure", class: "mb-3") do
      para "The host's action brings a companion along, and the companion raises. The " \
           "action still succeeded, so the response is a 200: the host re-renders with " \
           "its counter advanced, and the error appears only in the companion's own box.",
           class: "text-muted"
      companion_host
      flaky_companion
    end
  end

  def render_stream_outage_drill
    card(title: "Live-stream outage", class: "mb-3") do
      order_id = Logistics::Shipment.last&.order_id
      if order_id
        para "Open an order with shipments and flip its outage switch: the live feed " \
             "degrades through countdown frames to a closed stream with a resume button.",
             class: "text-muted"
        a "Open a shipping order", href: "/orders/#{order_id}", class: drill_button
      else
        para "No shipments yet — let the simulator run a minute, then come back.",
             class: "text-muted"
      end
    end
  end
end
