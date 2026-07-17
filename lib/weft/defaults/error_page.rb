# frozen_string_literal: true

module Weft
  module Defaults
    # Gem-default full-document page rendered for traditional (non-htmx)
    # responses when an error falls through to the Page recovers chain
    # and no user override matches. Thin wrapper around ErrorComponent.
    class ErrorPage < Weft::Page
      self.page_path = "/_weft/error"

      param :exception
      param :request_path
      param :status_code

      def build(attributes = {})
        attributes[:title] ||= "Error"
        super
        insert_tag(
          Weft::Defaults::ErrorComponent,
          exception: @params.exception,
          request_path: @params.request_path,
          status_code: @params.status_code
        )
      end
    end
  end
end
