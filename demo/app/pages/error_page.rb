# frozen_string_literal: true

# Full-document error page for Dropship Co. Subclasses ApplicationPage to
# inherit the design system and navbar — so users see a familiar surface even
# when something has failed. Wired in via Weft.configuration.error_page.
class ErrorPage < ApplicationPage
  self.page_path = "/error"

  # Page-level auto-injected attribute schema. The Router's schema-gated
  # injection uses these to know what to populate before rendering.
  attribute :exception
  attribute :request_path
  attribute :status_code

  def build(attributes = {})
    attributes[:title] ||= "Error"
    super
    insert_tag(
      ErrorComponent,
      exception: @attrs.exception,
      request_path: @attrs.request_path,
      status_code: @attrs.status_code
    )
  end
end
