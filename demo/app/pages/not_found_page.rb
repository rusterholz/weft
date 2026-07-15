# frozen_string_literal: true

# Full-document not-found page for Dropship Co. Subclasses ApplicationPage so
# the navbar is available — users can navigate away from a 404 easily.
# Wired in via Weft.configuration.not_found_page.
class NotFoundPage < ApplicationPage
  self.page_path = "/not_found"

  param :request_path
  param :status_code

  def build(attributes = {})
    attributes[:title] ||= "Not found"
    super
    insert_tag(
      NotFoundComponent,
      request_path: @params.request_path,
      status_code: @params.status_code
    )
  end
end
