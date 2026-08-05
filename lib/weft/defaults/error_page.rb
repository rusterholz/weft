# frozen_string_literal: true

require "weft/page"

module Weft
  module Defaults
    # Gem-default full-document page rendered for traditional (non-htmx)
    # responses when an error falls through to the Page recovers chain
    # and no user override matches. Thin wrapper around ErrorComponent.
    class ErrorPage < Weft::Page
      self.page_path = "/_weft/error"

      param :exception
      param :request_path, type: :string
      param :status_code, type: :integer

      title "Error"

      # The component reads the same request the page did — recovery values
      # ride as overlays and reach every depth — so handing them over as
      # builder kwargs would only render them as HTML attributes on the error
      # box, exception message and all.
      def build(attributes = {})
        super
        insert_tag(Weft::Defaults::ErrorComponent)
      end
    end
  end
end
