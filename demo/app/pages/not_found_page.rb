# frozen_string_literal: true

# Full-document not-found page for Dropship Co. Subclasses ApplicationPage so
# the navbar is available — users can navigate away from a 404 easily.
# Wired in via Weft.configuration.not_found_page.
class NotFoundPage < ApplicationPage
  self.page_path = "/not_found"

  param :request_path, type: :string
  param :status_code, type: :integer

  title "Not found"

  # The component resolves these from the same request, so passing them here
  # would only paint them onto its wrapper as HTML attributes.
  def build(attributes = {})
    super
    insert_tag(NotFoundComponent)
  end
end
