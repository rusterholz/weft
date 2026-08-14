# frozen_string_literal: true

module Drills
  # Succeeds at its own action while the companion it brings along fails.
  # The response is a 200 carrying this component's fresh render plus the
  # companion's error card in the companion's own slot — the action happened,
  # and only the part that broke says so.
  class CompanionHostComponent < Weft::Component
    builder_method :companion_host

    param :runs, type: :integer, default: 0

    performs(:break_companion) { |params| { runs: params.runs + 1 } }

    brings Drills::FlakyCompanion, on: :break_companion do
      { breaking: true }
    end

    def build(attributes = {})
      super
      add_class "content-card mb-2"
      div(class: "content-card-header") { h2 "Host" }
      div(class: "content-card-body") do
        para "This component's action has run #{params.runs} time(s) and keeps working.",
             class: "text-muted"
        button "Break the companion", class: "btn btn-sm btn-outline-secondary",
                                      action: :break_companion
      end
    end
  end
end
