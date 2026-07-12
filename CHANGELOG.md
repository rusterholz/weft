# Changelog

## v0.1.0 (2026-07-12)

First usable release. Weft is component-oriented hypermedia for Ruby: components declare their structure, their data, and their interactive behaviors, and the framework derives the routing, request handling, and client-side wiring automatically.

### New Features:

- **Components and pages** – Subclass `Weft::Component` and `Weft::Page`, declare `attribute`s, and build HTML in Ruby via Arbre:
  - Components render standalone fragments or compose into pages through generated builder methods (`builder_method :name`)
  - Declared attributes resolve from request parameters with defaults and type coercion, and reach your code as `attrs.whatever`
  - Pages carry the document shell: title, stylesheets, scripts, inline CSS, all inheritable down the page hierarchy
- **The verb DSL** – One-line declarations for dynamic behavior:
  - `performs :name` – user-initiated actions: run your callable, re-render the component
  - `transfers :name, to: Other` – actions that render a different component in the caller's place
  - `dismisses :name` – actions that remove the component from the DOM
  - `refreshes every:` / `refreshes on:` – client re-fetches on a timer (whole or fractional seconds, down to a 1ms floor) or when a page event fires
  - `pushes every:` – the server streams re-renders over SSE, with an immediate first frame for new subscribers
  - `triggers "event"` – announce action responses to the rest of the page
  - `includes Other` – companion components ride along out-of-band in action responses
  - `recovers from:, with:` – declarative error behavior per class
- **Auto-routing** – Components route at `/_components/<name>` and pages at name-derived paths, with the conventional class-name suffix stripped (`OrdersPanelComponent`, `OrdersPanel`, and `DashboardPage`, `Dashboard` all route without ceremony):
  - Explicit overrides via `self.page_path` and `self.component_path =`; global knobs for the component prefix and stream suffix
  - Routability inferred from declared state, with `abstract!` / `routable!` as escape hatches
  - SSE stream endpoints generated automatically for every pushing component
- **Route collision detection** – Two routable classes resolving to the same effective path raise `Weft::InvalidDefinition` naming both, lazily on the first request. Code reloaders that redefine a class prune the stale registration automatically; `Weft.registry.clear` gives reload integrations and tests a full reset
- **Element kwargs** – `action:`, `loads:`, `trigger:`, `navigate:`, and `push_url:` work on any element at any nesting depth, with `target:` and `swap:` refinements on `loads:` and the shorthands. Raw htmx attributes pass through untouched, side by side with what the kwargs expand to
- **Interaction shorthands** – `tooltip:`, `modal:`, `lazy:`, `load_more:`, `infinite_scroll:`, `live_search:`, `tabs:`, `inline_expand:`, and `retry:` — named presets over the `loads:` machinery with the trigger and swap details baked in. Register your own vocabulary with `Weft.register_shorthand`
- **Error handling** – A semantic error family under `Weft::Error` (`InvalidConfiguration`, `InvalidDefinition`, `InvalidUsage`, and the `HTTPError` classes such as `Weft::NotFound` and `Weft::Unprocessable`):
  - The `recovers` chain renders declared fallbacks with semantic status codes (a validation failure is a `422` whose body is the component wearing its error state)
  - Recovery targets receive schema-gated context — `:exception`, `:request_path`, `:status_code`, `:component_id`, `:retry_url` — only where declared
  - Brand the defaults app-wide via the `error_component` / `error_page` / `not_found_page` / `not_found_component` knobs, or per class with explicit `recovers` declarations
  - The gem-default error components offer one-click retry via the `retry:` shorthand
- **Configuration** – `Weft.configure` covers development reloading (`auto_reload`, `reload_paths`), logging (`Weft.logger`, stdout by default; `log_level`, `router_logging`), static asset bundles (`static_assets` with named bundles, path-containment checks, and `assets:` resolution on `register_stylesheet` / `register_script`), htmx delivery (`include_htmx`, `include_sse_ext`), and routing (`component_path`, `stream_suffix`)
- **Security posture** – The htmx core and SSE-extension scripts Weft includes are subresource-integrity pinned; `register_script` forwards `integrity:` / `crossorigin:` (and any other attributes) to the tag for your own CDN scripts
- **Documentation** – A complete set under `docs/`: a build-your-first-app tutorial; references for the DSL, routing, error handling, configuration, and the Arbre HTML layer; an application-patterns guide (service objects, databases, background jobs, authentication, CSRF, testing); and a twenty-one-page examples catalog with captured wire traffic that deliberately covers the ground of htmx's own examples
- **Demo app** – A complete Sinatra + Weft application under `demo/`, exercising the feature surface end to end
