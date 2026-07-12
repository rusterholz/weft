# frozen_string_literal: true

module Weft
  module Defaults
    # Gem-default full-document page rendered for traditional (non-htmx)
    # responses when a NotFound error falls through to the Page recovers
    # chain. Thin wrapper around NotFoundComponent.
    class NotFoundPage < Weft::Page
      self.page_path = "/_weft/not_found"

      attribute :request_path
      attribute :status_code

      def build(attributes = {})
        attributes[:title] ||= "Not found"
        super
        insert_tag(
          Weft::Defaults::NotFoundComponent,
          request_path: @attrs.request_path,
          status_code: @attrs.status_code
        )
      end
    end
  end
end
