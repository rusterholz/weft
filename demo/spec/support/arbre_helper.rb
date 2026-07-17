# frozen_string_literal: true

# Test helper for rendering Arbre components in isolation.
#
# This pattern will eventually become part of Weft's testing support.
# The idea: render a component in a minimal Arbre::Context, then assert
# on the HTML output, CSS classes, or content.
module ArbreHelper
  # Renders an Arbre block and returns the first top-level element.
  #
  #   component = render_arbre { stat_card label: "Orders", value: 42 }
  #   expect(component.to_s).to include("42")
  #
  def render_arbre(assigns = {}, &)
    Arbre::Context.new(assigns, nil, &).children.first
  end

  # Renders an Arbre block and returns the full HTML string.
  #
  #   html = render_arbre_html { status_badge "shipped" }
  #   expect(html).to include("badge-shipped")
  #
  def render_arbre_html(assigns = {}, &)
    Arbre::Context.new(assigns, nil, &).to_s
  end

  # Renders a Weft::Context block and returns the first top-level element.
  # Use for Weft::Components that need action:/trigger: expansion. Pass
  # `wire:` to simulate request params — components resolve their declared
  # params from it, exactly as they would from a query string.
  def render_weft(assigns = {}, wire: {}, &)
    Weft::Context.new(assigns, nil, wire_params: wire, &).children.first
  end

  # Renders a Weft::Context block and returns the full HTML string.
  def render_weft_html(assigns = {}, wire: {}, &)
    Weft::Context.new(assigns, nil, wire_params: wire, &).to_s
  end
end
