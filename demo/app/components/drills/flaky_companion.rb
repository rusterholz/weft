# frozen_string_literal: true

module Drills
  # Renders happily on the page, and fails when it rides along as a companion.
  # CompanionHostComponent's `includes` block hands it `breaking: true`, which
  # is the only thing that makes it raise — so the drill can show the same
  # component in both states without a global flag.
  class FlakyCompanion < Weft::Component
    builder_method :flaky_companion

    # :slot leads the declarations, so it — not :breaking — is what the DOM id
    # derives from. Identity has to survive the delta, or the error fragment
    # would be addressed to a slot that has never been on the page.
    param :slot, type: :string, default: "drill"
    param :breaking, type: :boolean, default: false

    def build(attributes = {})
      super
      raise "the companion drill exploded, as requested" if params.breaking

      add_class "content-card"
      div(class: "content-card-header") { h2 "Companion" }
      div(class: "content-card-body") do
        para "Riding along quietly. Press the button above and this box — and only " \
             "this box — becomes an error card.", class: "text-muted mb-0"
      end
    end
  end
end
