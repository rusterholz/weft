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

  title "Error"

  # The component reads the same request this page did — recovery values ride
  # as overlays and reach every depth — so it needs nothing handed over. Passing
  # them as builder kwargs would name declared params at the call site, which
  # weft renders as HTML attributes: the exception message would sit in the
  # markup even with verbose_error_pages off, where the visible text is hidden
  # and the page therefore *looks* safe.
  def build(attributes = {})
    super
    insert_tag(ErrorComponent)
  end
end
