# Changelog

## v0.2.0 (unreleased)

Weft's inputs model grows up: four declared ways to get a component what it needs, values that flow down the render tree, and one universe of state per request. Also typed wire params, one-call app loading, self-healing streams, and 404s you can brand.

### New Features:

- **Four Doors Into `params`** – Declare what a component needs; read it back the same way whatever the source. Full model in [the DSL reference](docs/dsl.md#params).
  - `param` – wire state from the query string, path, or body
  - `receives` – rich objects the call site hands over; required unless you declare a default
  - `derives` – a block that runs at most once per render, and only if something reads it
  - `defines` – static values a subclass pins; sugar over `derives`
  - Two doors on one key resolve either way: handed over when embedded, self-fetching when standalone
  - `dependent!` marks a component that only makes sense inside a parent

- **Typed Wire Params** (`type:`) – `param :page, type: :integer` reads `?page=2` as an Integer, with `:string`, `:float`, `:boolean`, and `:decimal` completing the vocabulary. Bad declarations fail at class-load time, not mid-request.

- **Ancestor Navigation** (`closest` / `enclosing`) – A nested component finds an ancestor and reads its identity, so it can aim at that ancestor instead of being hand-fed a target at every call site. Bang variants raise `Weft::AncestorNotFound`.

- **One-Call App Loading** (`Weft.configure_autoloading`) – Point Weft at your app directories and [Zeitwerk](https://github.com/fxn/zeitwerk) takes over; every component and page is registered and routable before the first request.
  - `reload: true` applies edits, new files, and deletions on the next request, route registry in sync
  - `Weft.registry.evict` and `Weft.configuration.refresh_stale_classes!` are public, for hand-rolled reloaders

- **Self-Healing Live Streams** – `recovers` now protects SSE pushes like any other render, and a stream that keeps failing no longer errors forever.
  - Error budget set gem-wide or per-component
  - Recovery components can declare `param :attempts_remaining` to tell "still retrying" apart from "gave up"
  - A new `reopen_stream:` preset, providing one-click resume for a failed stream
  - `pushes immediate: false` holds the first frame one interval, for snapshots that only mean something after a push cycle

- **Branded Not-Found Pages** – `recovers from: Weft::NotFound, with: YourNotFoundPage` now works the way it was always documented, on every 404 pathway; mounted as middleware, a downstream app's own 404s pass through untouched.
  - **Map your own errors** (`status:`) – `recovers from: ActiveRecord::RecordNotFound, with: NotFoundPage, status: 404` gives your exceptions honest wire semantics

- **One Universe Per Request** – A response resolves against the request's own wire params end to end — action re-render, `transfers` hand-off, or recovery — so a nested component keeps reading what it declares with no encloser relaying it. Hashes returned from verb blocks overlay that universe for everything the response renders.

- **Actions That Read What Your Component Knows** – Every verb block now sees the same `params` that `build` does, so a lookup a component already declares isn't written again inside each action. (`receives` stays out: a request over the wire has no call site.)
  - One query per response — a record the callable loads is already loaded for the re-render, its companions, and any transfer target
  - A `recovers` block is handed the state the request had reached when it broke
  - Two one-time warnings name a `derives` block that can never run

- **Companions Ride Along Smarter** (`includes`) – A companion renders as an out-of-band child of the component it accompanies, inheriting its params, with its block returning a delta for that companion alone.
  - `on:` takes arrays, and matches your own `transfers` actions
  - `when: :transferred` scopes a companion to transfer arrivals; declare both for a union
  - A companion that raises walks its **own** `recovers` chain into its **own** slot while the primary's render, status, and announcement stand — streams included, and it never spends their attempts budget

- **Announcements That Name Their Action** (`triggers ..., on:`) – Events are no longer welded to every action a component has, so subscribers stop refetching for an action that changed nothing. Arrays accepted.

- **Deletions Without Ceremony** (`dismisses`) – A successful delete-swap responds with an empty body, retiring the guard clause against the just-deleted record. Companions still ride along, and `dismisses` now takes `target:`.
  - A recovery fragment adopts the failing component's wrapper tag, so a failed row delete yields an error `<tr>`, not a `<div>` wedged into a table

- **Call-Site Wiring Overrides** (`target:` / `swap:`) – Every kwarg that wires a request now honors per-call overrides: the declaration supplies the default, the call site gets the final word.

- **Confirmation Dialogs** (`confirm:`) – Shows the browser-native dialog and fires the request only on OK. Works alongside any interaction kwarg, or standalone on a container.

- **Loud Wiring Failures** – A kwarg that is unmistakably Weft's but can't resolve raises `Weft::InvalidUsage` instead of rendering as a junk HTML attribute you would notice only when clicking did nothing. A `nil` value still means "not this time."

- **Declarative Page Titles** (`title`) – `title "Orders"`, or `title { |params| "Order ##{params.order.number}" }` when the tab should name the record. Inherited down a page hierarchy.

- **Two More Semantic Triggers** – `:change` fires when a select or checkbox changes value; `:click_once` caps an interaction at a single firing, the right default for anything that inserts rather than replaces. `inline_expand:` now bakes it in.

- **Inline Head Scripts** (`register_inline_js`) – The JavaScript sibling of `register_inline_css`, landing after the registered external scripts.

### Breaking Changes:

- **Renames** – All mechanical; rename call sites.
  - `attribute` → `param` and `attrs` → `params`, including every verb's block argument. Arbre's own HTML attributes are untouched
  - `shorthand` → `preset`: `Weft::Shorthands` → `Weft::Presets`, `register_shorthand` → `register_preset`, `Weft.shorthand` → `Weft.preset`. The element kwargs are unchanged
  - `Weft::Page.register_css` → `register_inline_css`
  - `weft_id` → `weft_dom_id`, `weft_id_for` → `weft_dom_id_for`; derived values unchanged
  - `Weft::Resolver#resolve` is now a class method, and `Weft::Params.extract_from` is removed

- **In-page param passing removed** – Components resolve their declared `param`s from the request at any nesting depth, so `orders_panel(status: params.status, page: params.page)` collapses to `orders_panel`. A builder kwarg naming a declared param now renders as a plain HTML attribute with a one-time warning; rich objects get `receives` instead.
  - `params` resolves at construction, so a `build` body can read it before `super`
  - `Weft::Context.new` accepts `wire_params:` for rendering outside the Router
  - `Component.render` / `Page.render` kwargs are now exactly what a query string would carry

- **The params bag flows down the render tree** – Each component starts from a copy of its nearest ancestor's resolved params: everything above it, nothing beside it. Its own sources still win, in a fixed order ([precedence table](docs/dsl.md#how-the-doors-combine)), and only its own declared `param`s serialize.

- **Defaults belong to whoever declares them** – A `default:` no longer travels: a child, or a `transfers` target, falls back to its own rather than an ancestor's. Everything actually supplied still flows down. Declare the value where it's meant to come from.

- **Wire coercion follows `type:`, not the default** – An untyped param passes its wire value through as a string. Add `type:` wherever a default used to do the coercing — flag params especially, since `"false"` is truthy without `type: :boolean`.

- **Removed: `auto_reload` / `reload_paths`** – Use `Weft.configure_autoloading(reload: true)`, which reloads more and keeps the routing registry in sync. `sinatra-contrib` is dropped, `zeitwerk` added; hand-rolled reloaders now call `Weft.registry.evict` explicitly.

- **The element-kwarg surface fails loudly** – Miswired kwargs raise `Weft::InvalidUsage` where they used to fall through as HTML attributes, and the `loads:`/preset "requires `swap:`/`target:`" errors move there from `ArgumentError`. Follow the messages — each names the kwarg and the repair.

- **Non-routable load targets raise** – A `loads:`, preset, or `navigate:` aimed at a non-routable class now raises at render time instead of 404ing at click time with nothing in the logs. Mark purely presentational targets `routable!`.

- **DOM ids skip unusable suffixes** – The id suffix rides only for non-blank scalars, so `""`, `nil`, and non-scalar values all derive the bare class id (`member-roster-[]` used to break `querySelector`). `false` now suffixes like `true`. Update CSS or tests matching the old forms.

- **Destructive-swap responses are empty** – A successful delete-swap responds `200` with no body where it used to carry a render htmx discarded. Out-of-band fragments still arrive.

- **Page titles are declared, not extracted** – `Weft::Page` no longer reads `:title` from the build attributes; a page still setting it leaves the tab reading "Weft" and a stray `title="..."` on `<html>`. Use the class-body `title`.

- **`inline_expand:` fires once** – The default trigger is now `:click_once`, so a repeat click can't insert a second copy. Drop any hand-written `trigger: "click once"`; declare `trigger: :click` to keep re-triggering.

- **Transfers responses carry the target's companions** – The *rendered* component's `includes` fire, not the transferring one's, and `on:` matches only a component's own action names. Scope arrivals with `when: :transferred`.

- **A failed render walks the chain of whatever was rendering** – A `transfers` target that raises during its own `build` is handled by the target's `recovers` chain. Declare the edge on the target, or on a shared base class.

- **The declarer's schema stays its own** – A transfer or recovery target projects its own declared schema and its own defaults; what crosses over is the state the request composed, so nothing already loaded is fetched twice.

- **One DOM slot, one companion** – Two companions resolving to the same DOM id can't both land, so Weft keeps the first, warns naming both declaration sites, and never builds the loser. A component's first param now decides which companions can coexist, not only where each lands.

- **Inclusion blocks return deltas, not replacements** – The hash adjusts a companion's picture instead of defining its entire wire. Clear a key explicitly (`{ key: nil }`) where a block used to withhold it.

- **Recovery fragments always wear the failing component's id** – Weft stamps identity onto every recovery fragment, so a target lands correctly whether or not it knows about any of this. `:component_id` is gone from the auto-injected params (six remain); drop the declaration and any `weft_dom_id` override that read it.

## v0.1.0 (2026-07-12)

First usable release. Weft is component-oriented hypermedia for Ruby: components declare their structure, their data, and their interactive behaviors, and the framework derives the routing, request handling, and client-side wiring automatically.

### New Features:

- **Components and Pages** (`Weft::Component`, `Weft::Page`) – Build HTML in Ruby with a component DSL over Arbre:
  - Describe structure in a `build` block and declare a component's inputs with `attribute` — they arrive from request parameters, coerced to type and filled with your defaults, and reach your code as `attrs.whatever`
  - Render a component as a standalone fragment or drop it into a page through a generated builder method (`builder_method :name`)
  - Pages carry the whole document shell — title, stylesheets, scripts, inline CSS — inheritable down a page hierarchy, so a shared layout costs nothing at each page
- **Interactive Behaviors** – One-line declarations that wire up dynamic behavior, no routes or JavaScript written by hand:
  - `performs :name` – a user-initiated action: run your callable, then re-render the component in place
  - `transfers :name, to: Other` – an action whose response renders a *different* component where the caller was
  - `dismisses :name` – an action that removes the component from the DOM
  - `refreshes every:` / `refreshes on:` – the client re-fetches the component on a timer (whole or fractional seconds, down to a 1ms floor) or whenever a named page event fires
  - `pushes every:` – the server streams re-renders over SSE, with an immediate first frame for every new subscriber
  - `triggers "event"` – announce an action's result to the rest of the page for other components to react to
  - `includes Other` – a companion component rides along out-of-band, updating a second region in the same response
  - `recovers from:, with:` – declare per-class error behavior
- **Automatic Routing** – Every component and page gets a URL with no route table to maintain: components at `/_components/<name>`, pages at name-derived paths, the conventional class-name suffix stripped (`OrdersPanelComponent` and `OrdersPanel`, `DashboardPage` and `Dashboard`, all route without ceremony):
  - Override explicitly with `self.page_path` and `self.component_path =`; tune the component prefix and stream suffix gem-wide
  - Routability is inferred from what a class declares, with `abstract!` / `routable!` to force it either way
  - Every pushing component gets its SSE stream endpoint generated automatically
- **Collision-Safe Routing** – If two routable classes would answer at the same URL, Weft raises `Weft::InvalidDefinition` naming both — on the first request, so you find out immediately. Code reloaders that redefine a class prune the stale registration automatically, and `Weft.registry.clear` gives reload integrations and tests a clean slate
- **Element-Level Wiring** – Attach behavior to any element at any nesting depth with `action:`, `loads:`, `trigger:`, `navigate:`, and `push_url:`, plus `target:` and `swap:` to refine where `loads:` and the shorthands land their response. Raw htmx attributes pass straight through, side by side with what the kwargs expand to
- **Interaction Shorthands** – Named one-word wirings over the `loads:` machinery, with the trigger and swap details baked in: `tooltip:`, `modal:`, `lazy:`, `load_more:`, `infinite_scroll:`, `live_search:`, `tabs:`, `inline_expand:`, and `retry:`. Register your own vocabulary with `Weft.register_shorthand`
- **Semantic Error Handling** – A full error family under `Weft::Error` (`InvalidConfiguration`, `InvalidDefinition`, `InvalidUsage`, and `HTTPError` classes like `Weft::NotFound` and `Weft::Unprocessable`), and a recovery system that renders the right fallback with the right status code:
  - The `recovers` chain renders declared fallbacks with semantic status codes — a validation failure becomes a `422` whose body is the component wearing its error state
  - Recovery targets receive schema-gated context — `:exception`, `:request_path`, `:status_code`, `:component_id`, `:retry_url` — only where they declare it
  - Brand the defaults app-wide via `error_component` / `error_page` / `not_found_page` / `not_found_component`, or override per class with explicit `recovers` declarations
  - The built-in error components offer one-click retry through the `retry:` shorthand
- **Configuration** – `Weft.configure` covers the operational surface: development reloading (`auto_reload`, `reload_paths`), logging (`Weft.logger`, stdout by default; `log_level`, `router_logging`), static asset bundles (`static_assets` with named bundles, path-containment checks, and `assets:` resolution on `register_stylesheet` / `register_script`), htmx delivery (`include_htmx`, `include_sse_ext`), and routing (`component_path`, `stream_suffix`)
- **Secure Script Delivery** – The htmx core and SSE-extension scripts Weft serves are subresource-integrity pinned out of the box, and `register_script` forwards `integrity:` / `crossorigin:` (and any other attributes) to the tag for your own CDN scripts
- **Documentation** – A complete set under `docs/`: a build-your-first-app tutorial; references for the DSL, routing, error handling, configuration, and the Arbre HTML layer; an application-patterns guide (service objects, databases, background jobs, authentication, CSRF, testing); and a twenty-one-page examples catalog with captured wire traffic that deliberately covers the ground of htmx's own examples
- **Demo Application** – A complete Sinatra + Weft application under `demo/`, exercising the feature surface end to end
