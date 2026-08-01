# frozen_string_literal: true

require "arbre"

require "weft/error"
require "weft/registry"

module Weft
  class Page < Arbre::Component
    # The asset surface of the page head: the register_* family (class-level
    # DSL, accumulate semantics — subclasses add atop their parents) plus the
    # rendering and URL-resolution machinery that emits them. Mixed into
    # Weft::Page alongside Head, whose build_head drives render_assets.
    module Assets
      def self.included(base) = base.extend(ClassMethods)

      HTMX_SRC = "https://unpkg.com/htmx.org@2.0.4"
      HTMX_ATTRS = {
        integrity: "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+",
        crossorigin: "anonymous"
      }.freeze
      HTMX_SSE_SRC = "https://unpkg.com/htmx-ext-sse@2.2.2/sse.js"
      HTMX_SSE_ATTRS = {
        integrity: "sha384-fw+eTlCc7suMV/1w/7fr2/PmwElUIt5i82bi+qTiLXvjRXZ2/FkiTNA/w0MhXnGI",
        crossorigin: "anonymous"
      }.freeze

      # Class-level registration DSL. Each register_* call accumulates; the
      # matching reader returns own + inherited entries in ancestor order.
      module ClassMethods
        # Register a stylesheet to include in the page head.
        #
        # Absolute URLs (http(s)://, protocol-relative //, leading /) render as-is.
        # Bare-relative paths resolve against a static_assets bundle: either the
        # one named via `assets:`, or the :default bundle if one is configured.
        # When neither applies, the path passes through unchanged and the browser
        # resolves it relative to the current page URL.
        #
        #   register_stylesheet "https://cdn.example.com/bootstrap.css"
        #   register_stylesheet "css/app.css"                   # resolves against :default
        #   register_stylesheet "tailwind/tw.css", assets: :vendor
        def register_stylesheet(href, assets: nil)
          own_stylesheets << { href: href, assets: assets }
        end

        # Register a script to include in the page head. Same resolution rules
        # as register_stylesheet. Additional kwargs become HTML attributes on
        # the <script> tag.
        #
        #   register_script "https://cdn.example.com/app.js", defer: "defer"
        #   register_script "js/app.js"                         # resolves against :default
        #   register_script "vendor/x.js", assets: :vendor, defer: "defer"
        def register_script(src, assets: nil, **html_attrs)
          own_scripts << { src: src, attrs: html_attrs, assets: assets }
        end

        # Register a block of inline CSS to include in the page head.
        # Each registered string emits as its own <style> tag (subclasses
        # add on top of their parent's contributions; nothing replaces).
        #
        #   register_inline_css <<~CSS
        #     .card { padding: 1rem; }
        #   CSS
        def register_inline_css(css)
          own_inline_css << css
        end

        # Register a block of inline JavaScript to include in the page head.
        # Same accumulate semantics as register_inline_css; emitted after the
        # registered external scripts, so registered libraries are in reach.
        #
        #   register_inline_js "htmx.logAll();"
        def register_inline_js(javascript)
          own_inline_js << javascript
        end

        # All registered stylesheets (own + inherited).
        def stylesheets
          if superclass.respond_to?(:stylesheets)
            superclass.stylesheets + own_stylesheets
          else
            own_stylesheets.dup
          end
        end

        # All registered scripts (own + inherited).
        def scripts
          if superclass.respond_to?(:scripts)
            superclass.scripts + own_scripts
          else
            own_scripts.dup
          end
        end

        # All registered inline CSS blocks (own + inherited).
        def inline_css
          if superclass.respond_to?(:inline_css)
            superclass.inline_css + own_inline_css
          else
            own_inline_css.dup
          end
        end

        # All registered inline JS blocks (own + inherited).
        def inline_js
          if superclass.respond_to?(:inline_js)
            superclass.inline_js + own_inline_js
          else
            own_inline_js.dup
          end
        end

        private

        def own_stylesheets = @own_stylesheets ||= []
        def own_scripts = @own_scripts ||= []
        def own_inline_css = @own_inline_css ||= []
        def own_inline_js = @own_inline_js ||= []
      end

      private

      def render_assets
        render_stylesheets
        render_htmx_script if Weft.configuration.include_htmx
        render_sse_script if include_sse_ext?
        render_scripts
        render_inline_js
        render_inline_css
      end

      def render_stylesheets
        self.class.stylesheets.each do |entry|
          link href: resolve_asset_url(entry[:href], assets: entry[:assets]), rel: "stylesheet"
        end
      end

      def render_scripts
        self.class.scripts.each do |entry|
          script(src: resolve_asset_url(entry[:src], assets: entry[:assets]), **entry[:attrs])
        end
      end

      def render_inline_js
        self.class.inline_js.each { |js| script { text_node js.html_safe } }
      end

      def render_inline_css
        self.class.inline_css.each { |css| style { text_node css.html_safe } }
      end

      def render_htmx_script
        script src: HTMX_SRC, **HTMX_ATTRS
      end

      def render_sse_script
        script src: HTMX_SSE_SRC, **HTMX_SSE_ATTRS
      end

      # Resolve the include_sse_ext configuration into a boolean. :auto defers
      # to the Registry; true/false short-circuit it.
      def include_sse_ext?
        case Weft.configuration.include_sse_ext
        when true then true
        when false then false
        else Weft.registry.any_sse_components?
        end
      end

      # Resolve a registered asset path to a final URL.
      #
      # - Absolute URLs (http(s)://, //, /) pass through unchanged. Passing an
      #   `assets:` kwarg alongside an absolute URL raises — the kwarg is only
      #   meaningful for relative paths, and accepting it silently would train
      #   callers to attach it everywhere "just in case."
      # - Bare-relative paths with an explicit `assets: :name` resolve against
      #   that bundle's root. Unknown bundle names raise with a list of
      #   configured names.
      # - Bare-relative paths without an `assets:` kwarg resolve against the
      #   :default bundle if one is configured; otherwise they pass through and
      #   the browser interprets them relative to the current page URL.
      def resolve_asset_url(path, assets: nil)
        return resolve_absolute_asset_url(path, assets) if absolute_asset_url?(path)

        resolve_relative_asset_url(path, assets)
      end

      def resolve_absolute_asset_url(path, assets)
        raise_absolute_with_assets_kwarg!(path, assets) if assets

        path
      end

      def resolve_relative_asset_url(path, assets)
        bundles = Weft.configuration.static_assets
        target = assets&.to_sym || (bundles.key?(:default) ? :default : nil)
        return path unless target

        bundle = bundles[target]
        raise_unknown_assets_bundle!(path, target, bundles) unless bundle

        "#{bundle[:root]}/#{path}"
      end

      def absolute_asset_url?(path)
        path.start_with?("http://", "https://", "//", "/")
      end

      def raise_absolute_with_assets_kwarg!(path, assets)
        raise Weft::InvalidUsage,
              "static asset #{path.inspect}: assets: #{assets.inspect} " \
              "is only meaningful for relative paths (absolute URLs render as-is)"
      end

      def raise_unknown_assets_bundle!(path, target, bundles)
        raise Weft::InvalidUsage,
              "static asset #{path.inspect} references assets bundle #{target.inspect}, " \
              "but no such bundle is configured. Configured bundles: #{bundles.keys.inspect}"
      end
    end
  end
end
