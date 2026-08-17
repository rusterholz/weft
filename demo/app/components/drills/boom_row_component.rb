# frozen_string_literal: true

module Drills
  # A table row whose delete action always fails server-side. Embedded on the
  # drills page (the row itself renders fine — only the action explodes) to
  # prove the destructive-swap error pathway: HX-Reswap overrides the delete
  # so the error shows instead of the row vanishing, and the fragment adopts
  # the row's tag, landing as valid table content.
  class BoomRowComponent < Weft::Component
    builder_method :boom_row

    # Both use the dual from the delete-row idiom: `receives` because the table
    # hands each row its own value at the call site, `param` because the row's
    # own delete action re-resolves it from the wire. Without the `receives`
    # half the kwargs would be chrome and every row would fall back to one
    # default — same text, and worse, the same DOM id.
    #
    # :row leads, so identity rides a slug rather than the display text: the
    # DOM id is a selector, and "Doomed row one" is not one.
    param :row, type: :string, default: "doomed"
    identifies_by :row
    receives :row
    param :label, type: :string, default: "Doomed row"
    receives :label

    dismisses(:remove) { |_params| raise "the delete drill exploded, as requested" }

    def tag_name
      "tr"
    end

    def build(attributes = {})
      super
      td params.label
      td(style: "width:2rem") do
        button "✕", class: "btn btn-sm btn-link p-0 text-danger", action: :remove,
                    confirm: "Delete this row? (The server will refuse.)"
      end
    end
  end
end
