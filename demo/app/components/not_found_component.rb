# frozen_string_literal: true

# Dropship Co.'s app-level not-found display. Subclasses
# Weft::Defaults::NotFoundComponent for the auto-injected param schema
# and overrides visuals to match the DropshipUI design system.
class NotFoundComponent < Weft::Defaults::NotFoundComponent
  # Rendered via Weft.configuration.not_found_component and the recovers chain,
  # not addressed directly — so it does not route. (abstract! does not inherit
  # from the gem default, hence the re-declaration.)
  abstract!

  def build(attributes = {})
    super
    set_attribute "style", "padding:0"
    add_class "content-card"
    children.clear

    div(class: "content-card-header") do
      h2 { text_node "Not found" }
      span(class: "badge-status badge-busy") { text_node "404" }
    end
    div(class: "content-card-body") do
      if Weft.configuration.verbose_error_pages && @params.request_path
        div(class: "mono", style: "font-size:0.8rem; color:#475569") do
          text_node @params.request_path
        end
      end
      a("Back to dashboard", href: "/", class: "btn btn-sm btn-outline-primary mt-3")
    end
  end
end
