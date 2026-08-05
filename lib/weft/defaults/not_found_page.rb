# frozen_string_literal: true

require "weft/page"

module Weft
  module Defaults
    # Gem-default full-document page rendered for traditional (non-htmx)
    # responses when a NotFound error falls through to the Page recovers
    # chain. Thin wrapper around NotFoundComponent.
    class NotFoundPage < Weft::Page
      self.page_path = "/_weft/not_found"

      param :request_path, type: :string
      param :status_code, type: :integer

      title "Not found"

      # See ErrorPage#build: the component resolves these from the same
      # request, so passing them here would only paint them onto the wrapper.
      def build(attributes = {})
        super
        insert_tag(Weft::Defaults::NotFoundComponent)
      end
    end
  end
end
