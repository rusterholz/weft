# frozen_string_literal: true

# Application base page for the Dropship Co. operations app. Subclass for
# every routable page in this app. Knows the app's navigable sections
# (Dashboard, Orders, Shipments, Drivers). Inherits the company's design
# language from DropshipUI::Page. The htmx-ext-sse script is auto-emitted
# by the gem when any registered component declares `pushes`.
class ApplicationPage < DropshipUI::Page
  abstract!
  builder_method :application_page
  adds_children_to :@main

  # Navbar chrome lives at the app layer (the navbar itself is rendered by
  # ApplicationPage). Tokens like --ds-mono / --ds-border come from the
  # design-system stylesheet registered on DropshipUI::Page.
  register_css <<~CSS
    .navbar { border-bottom: 1px solid var(--ds-border); }
    .navbar-brand { font-family: var(--ds-mono); font-weight: 700; letter-spacing: -0.5px; }
    .navbar-brand .brand-dot {
      display: inline-block; width: 8px; height: 8px;
      background: #059669; border-radius: 50%; margin-right: 6px; vertical-align: middle;
    }
    .nav-link.active { font-weight: 600; }
  CSS

  NAVIGABLE_PAGES = [
    ["/", "Dashboard"],
    ["/orders", "Orders"],
    ["/shipments", "Shipments"],
    ["/drivers", "Drivers"]
  ].freeze

  def build(attributes = {})
    @current_path = attributes.delete(:current_path) || "/"
    super
    render_navbar
    @main = div(class: "container-fluid px-4")
  end

  private

  def render_navbar
    nav(class: "navbar navbar-expand-sm bg-white") do
      div(class: "container-fluid px-4") do
        a(class: "navbar-brand", href: "/") do
          span(class: "brand-dot")
          text_node "Dropship Co."
        end
        render_nav_links
      end
    end
  end

  def render_nav_links
    ul(class: "navbar-nav ms-4 gap-1") do
      NAVIGABLE_PAGES.each do |path, label|
        li(class: "nav-item") do
          css = @current_path == path ? "nav-link active" : "nav-link"
          a label, class: css, href: path
        end
      end
    end
  end
end
