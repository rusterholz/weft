# frozen_string_literal: true

# Full-document error page for Dropship Co. Subclasses ApplicationPage to
# inherit the design system and navbar — so users see a familiar surface even
# when something has failed. Wired in via Weft.configuration.error_page.
class ErrorPage < ApplicationPage
  self.page_path = "/error"

  # Page-level auto-injected param schema. The Router's schema-gated
  # injection uses these to know what to populate before rendering.
  param :exception
  param :request_path, type: :string
  param :status_code, type: :integer

  def build(attributes = {})
    attributes[:title] ||= "Error"
    super
    insert_tag(
      ErrorComponent,
      exception: @params.exception,
      request_path: @params.request_path,
      status_code: @params.status_code
    )
  end
end
