# Changelog

## v0.2.0 (unreleased)

### Breaking changes:

- **`attribute` → `param`, `attrs` → `params`.** The DSL for a component's or page's inputs is renamed. Declare inputs with `param :name` (was `attribute :name`), and read the resolved values through `params` instead of `attrs` (`params.status`, `params[:page]`, `params.to_h`). The block argument to verb declarations — `performs`, `transfers`, `dismisses`, `recovers`, `includes` — is now `params`. Arbre's own HTML tag attributes are unaffected: `build(attributes = {})`, `set_attribute`, and element hashes like `class:` and `data:` keep their names. To migrate, rename `attribute` → `param` and `attrs` → `params` across your components, pages, and verb blocks.

- **Params travel their own channel — in-page param passing is removed.** Components and pages now resolve their declared `param`s directly from the request's wire params (query, path, and body values), at any nesting depth: a component embedded in a page sees the same wire params the page does, so call sites like `orders_panel(status: params.status, page: params.page)` reduce to `orders_panel`. Passing a builder kwarg that names a declared param no longer fills `params` — it renders as a plain HTML attribute, with a one-time warning per class and key (param names can legitimately double as HTML attribute names, so this is not an error). Rich objects handed by the caller get their own declaration instead: see `receives` under New features. Also part of this change:
  - `params` is resolved when a component is instantiated, so build bodies can read it *before* calling `super` — deriving a page title from a record looked up by param, for example.
  - `Component.render` / `Page.render` kwargs are now exactly what a request's query string would carry; undeclared keys are ignored instead of becoming HTML attributes on the wrapper element.
  - `Weft::Context.new` accepts `wire_params:` to simulate request params when rendering outside the Router — the pattern for component specs.
  - In a plain `Arbre::Context`, components resolve their declared defaults (there is no wire source to read).
  - `Weft::Resolver#resolve` is now a class method (`Weft::Resolver.resolve`); `Weft::Params.extract_from` is removed.

- **The params bag flows down the render tree.** Within a single render, each component starts from a copy of its nearest ancestor component's (or page's) resolved params: a component sees everything *above* it, nothing *beside* it. A bare `shipments_card` embedded in a page that declares `param :order_id` reads `params.order_id` without declaring anything. When a component declares a key of its own, its sources win in a fixed order: a handed value (`receives`) beats the component's own wire value, which beats an inherited one, which beats the declared default. Serialization is unaffected: only a component's *own* declared `param`s appear in its refresh/stream URLs and action payloads (`hx-vals`) — inherited values are delivery convenience, not part of the refresh contract. If a nested component previously relied on a param resolving to its own default while an ancestor held a different value for the same name, it now inherits the ancestor's value.

- **`shorthand` → `preset`; `register_css` → `register_inline_css`.** The named interaction presets — `tooltip:`, `modal:`, `lazy:`, `load_more:`, `infinite_scroll:`, `live_search:`, `tabs:`, `inline_expand:`, and `retry:` — are now registered and looked up as *presets*: `Weft::Shorthands` → `Weft::Presets`, `Weft.register_shorthand` → `Weft.register_preset`, and `Weft.shorthand` → `Weft.preset`. The element kwargs are unchanged — `tooltip:`, `modal:`, `lazy:` and friends still work exactly as before. Separately, `Weft::Page.register_css` → `register_inline_css`, restoring naming parity with `register_stylesheet`. To migrate, rename any custom `register_shorthand` calls to `register_preset`, and `register_css` to `register_inline_css`.

### New features:

- **`receives :name` — declared caller hand-offs.** Values a call site hands to a component — rich objects, computed values, anything that can't ride a URL — now have a first-class declaration. `receives :order` means `order_row(order: order)` fills `params.order`; the kwarg never becomes an HTML attribute. A missing required hand-off raises `Weft::NotReceived` at the call site; declaring a default (`receives :page_num, default: 1` — even an explicit `default: nil`) makes it optional. Hand-offs are server-side: they never serialize into URLs, and declaring them doesn't make a component routable. This replaces the v0.1 pattern of pulling rich objects out of `attributes` before `super`.
  - **Dual-source keys.** Declaring both `param :status` and `receives :status` gives a key two doors: embedded call sites hand the value over, and it serializes as a wire param so a standalone refresh reconstructs it — a self-refreshing card embedded with `status_card(status: "hot")` keeps its status across refreshes.
  - **`dependent!`** — an alias of `abstract!` for components that rely on hand-offs: "my parent passes this in every time, so serving me standalone makes no sense."
  - **Refresh-safety lint.** At route validation, a routable component declaring a required hand-off with no wire dual logs a warning — such a component renders embedded but would raise on every refresh. Mark it `dependent!` or declare a dual.

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
