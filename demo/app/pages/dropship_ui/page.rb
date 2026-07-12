# frozen_string_literal: true

module DropshipUI
  # Dropship Co.'s portable design-language Page. Concrete apps subclass
  # via their own ApplicationPage; this class itself does not route and
  # carries no app-specific knowledge (no navbar links, no app-specific
  # script extensions). Apps add those at their own ApplicationPage layer.
  #
  # What lives here: company-wide branding (Bootstrap, JetBrains Mono
  # font) and the design-system stylesheet that gives cards, badges,
  # tables, tooltips, and the page chrome their look.
  class Page < Weft::Page
    abstract!

    register_stylesheet "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css"
    register_stylesheet "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
    register_stylesheet "css/design-system.css"

    def build(attributes = {})
      attributes[:title] ||= "Dropship Co."
      super
    end
  end
end
