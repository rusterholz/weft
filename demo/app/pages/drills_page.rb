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
  DRILLS = %i[missing_record unreadable_id unreadable_request routing_miss validation
              component_failure destructive_swap page_failure redirect_recovery
              companion_failure stream_outage].freeze

  # Well-formed and guaranteed absent. An obviously fake id would leave the
  # drill ambiguous — the branded 404 looks the same whether the route matched
  # and the lookup found nothing, or no route matched at all. This one matches
  # the :order_id route, reaches a real find, and comes back empty.
  # It also has to be well-formed to reach the lookup at all: `type: :uuid`
  # refuses a non-uuid before any query, which is the drill after it.
  ABSENT_ID = "ffffffff-ffff-ffff-ffff-ffffffffffff"

  # Deliberately not a uuid. The paired opposite of ABSENT_ID.
  UNREADABLE_ID = "wombat"

  # The three detail routes, which the two id drills exercise as a pair.
  DETAIL_ROUTES = { "order" => "/orders", "shipment" => "/shipments", "driver" => "/drivers" }.freeze

  # Two query strings that never become keys and values: a stray percent sign
  # is invalid encoding, and one key claiming to be both a list and a hash is
  # a shape nothing can resolve.
  UNPARSEABLE_QUERIES = { "Invalid encoding" => "q=%", "Conflicting shapes" => "a[]=1&a[b]=2" }.freeze

  def build(attributes = {})
    super
    div(class: "page-header") { h1 "Error drills" }
    DRILLS.each { |drill| send(:"render_#{drill}_drill") }
  end

  private

  def current_path = "/drills"
  def drill_button = "btn btn-sm btn-outline-secondary"

  # The two id drills are one card with a different id in the links, which is
  # the point of them: same routes, same lookups, different answer.
  def id_drill(title:, id:, label:, blurb:)
    drill_card(title: title, blurb: blurb) do
      div(class: "d-flex gap-2") do
        DETAIL_ROUTES.each do |noun, path|
          a format(label, noun), href: "#{path}/#{id}", class: drill_button
        end
      end
    end
  end

  def render_missing_record_drill
    id_drill(title: "Branded 404 — missing record", id: ABSENT_ID, label: "Missing %s",
             blurb: "Detail pages use bare ActiveRecord lookups; one recovers declaration maps " \
                    "RecordNotFound to the branded not-found page with a genuine 404.")
  end

  def render_unreadable_id_drill
    id_drill(title: "Branded 400 — unreadable id", id: UNREADABLE_ID, label: "Unreadable %s id",
             blurb: "The same routes, given something that is not a uuid at all. A declared type " \
                    "refuses it before any lookup runs, so the answer is 400 rather than the 404 " \
                    "above: “no such record” and “that is not an id” are different answers, and " \
                    "only one of them needs the database to find out.")
  end

  # The pair to the drill above, one step further out: there the id was
  # unreadable, here the whole request is.
  def render_unreadable_request_drill
    drill_card(title: "Branded 400 — unreadable request",
               blurb: "The orders page, asked for with a query string that cannot be parsed at " \
                      "all. There is no key to name and no value to hand back, so nothing can be " \
                      "redrawn — but the answer is still the branded page with a genuine 400, " \
                      "because an unreadable request is the caller's mistake, not the server's.") do
      div(class: "d-flex gap-2") do
        UNPARSEABLE_QUERIES.each do |label, query|
          a label, href: "/orders?#{query}", class: drill_button
        end
      end
    end
  end

  def render_routing_miss_drill
    drill_card(title: "Branded 404 — routing miss",
               blurb: "No route, no page: the router's not-found chain renders the branded page. " \
                      "The path is freshly minted on every render, so it can't quietly be a " \
                      "route that happens to answer.") do
      a "Visit an unrouted path", href: "/no-such-path-#{SecureRandom.hex(4)}", class: drill_button
    end
  end

  def render_validation_drill
    drill_card(title: "Validation failure (422)",
               blurb: "Submit the order form with no items selected — it recovers in place, " \
                      "keeping your input and showing the message.") do
      a "Open the order form", href: "/orders/new", class: drill_button
    end
  end

  def render_component_failure_drill
    drill_card(title: "Component failure (500)",
               blurb: "Click-loads a component whose build always raises: the branded error card " \
                      "swaps in where the button was, and the rest of this page is untouched. " \
                      "Retry re-fails, on purpose.") do
      button "Trigger component failure", load_more: Drills::BoomComponent, class: drill_button
    end
  end

  def render_destructive_swap_drill
    drill_card(title: "Destructive-swap failure",
               blurb: "Each row's delete always fails server-side: the error swaps in as a real " \
                      "table row where the deleted one would have vanished — the rest of the " \
                      "table is untouched.") do
      table(class: "table table-data mb-0") do
        tbody do
          boom_row row: "one", label: "Doomed row one"
          boom_row row: "two", label: "Doomed row two"
        end
      end
    end
  end

  def render_page_failure_drill
    drill_card(title: "Page failure (500)",
               blurb: "A full-document render that raises: the branded error page takes over.") do
      a "Explode a full page", href: "/drills/boom", class: drill_button
    end
  end

  def render_redirect_recovery_drill
    drill_card(title: "Redirect recovery",
               blurb: "This component recovers from its failure by transferring to a page: htmx " \
                      "follows the HX-Redirect and you land on the dashboard.") do
      button "Trigger redirect recovery", load_more: Drills::RedirectBoomComponent,
                                          class: drill_button
    end
  end

  def render_companion_failure_drill
    drill_card(title: "Companion failure",
               blurb: "The host's action brings a companion along, and the companion raises. The " \
                      "action still succeeded, so the response is a 200: the host re-renders with " \
                      "its counter advanced, and the error appears only in the companion's own " \
                      "box.") do
      companion_host
      flaky_companion
    end
  end

  # The one drill whose blurb depends on the world: with no shipments there is
  # nothing to open, so it says so instead of offering a dead link.
  def render_stream_outage_drill
    order_id = Logistics::Shipment.last&.order_id
    drill_card(title: "Live-stream outage", blurb: stream_outage_blurb(order_id)) do
      a "Open a shipping order", href: "/orders/#{order_id}", class: drill_button if order_id
    end
  end

  def stream_outage_blurb(order_id)
    return "No shipments yet — let the simulator run a minute, then come back." unless order_id

    "Open an order with shipments and flip its outage switch: the live feed degrades " \
      "through countdown frames to a closed stream with a resume button."
  end
end
