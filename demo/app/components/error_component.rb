# frozen_string_literal: true

# Dropship Co.'s app-level error display, and the canonical example of the
# user-extension pattern: subclass Weft::Defaults::ErrorComponent to inherit the
# auto-injected param schema (:exception, :request_path, :status_code,
# :component_id, :retry_url), restyle it however you like, and wire it in via
# Weft.configuration.error_component (see config/environment.rb).
#
# Note that the retry control is rendered through the gem's :retry shorthand
# (see #render_retry_button) rather than hand-written htmx — the app expresses
# only intent ("retry, using this URL") and inherits the standard
# re-fetch-and-outerHTML-swap-the-error-box behavior for free.
class ErrorComponent < Weft::Defaults::ErrorComponent
  # Rendered via Weft.configuration.error_component and the recovers chain,
  # not addressed directly — so it does not route. (abstract! does not inherit
  # from the gem default, hence the re-declaration.)
  abstract!

  def build(attributes = {})
    super
    # Replace the inherited container styling with a DropshipUI Card-like surface.
    set_attribute "style", "padding:0"
    add_class "content-card"
    children.clear

    div(class: "content-card-header", style: "background:#fef2f2; border-color:#fecaca") do
      h2(style: "color:#991b1b") { text_node "Something went wrong" }
      span(class: "badge-status badge-busy") { text_node "Error" } if @params.status_code
    end
    div(class: "content-card-body") do
      render_verbose_body if Weft.configuration.verbose_error_pages && @params.exception
      render_retry_button if @params.retry_url
    end
  end

  private

  def render_verbose_body
    exc = @params.exception
    div(class: "mono", style: "font-size:0.8rem; color:#7f1d1d; margin-bottom:0.75rem") do
      text_node "#{exc.class}: #{exc.message}"
    end
  end

  # The :retry shorthand supplies the htmx wiring — no hand-written hx-* here.
  # It outerHTML-swaps the closest .weft-error box, a class this component keeps
  # (inherited from the gem default) even though it restyles as a content-card.
  def render_retry_button
    button "Retry", retry: @params.retry_url, class: "btn btn-sm btn-outline-danger"
  end
end
