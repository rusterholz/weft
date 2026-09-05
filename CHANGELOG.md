# Changelog

## v0.3.0 (unreleased)

Weft learns to say what a thing *is*: components name their own identity instead of inheriting one by accident, and the types they declare become promises Weft keeps — so sibling instances stay individually addressable, a malformed request fails where the mistake is, and the words for what a class body does mean one thing each.

### New Features:

- **Errors That Hand Back What You Typed** – When a wire value is refused, the error carries every violation from that request: the key, what the type wanted, and the raw value exactly as it arrived. So a `recovers` edge can redraw the form with `wombat` still sitting in the age field and a message beside it, instead of the zero a lenient conversion would have put there.
  - Every bad field in one pass, so a form with three of them reports three rather than making the visitor fix them one round trip at a time
  - The fields that *did* arrive cleanly are still in `params`, so a redraw keeps the rest of the form intact

- **Required Params** (`required:`) – `param :order_id, type: :uuid, required: true` says a request without it isn't a request you'll serve, and Weft answers 400 rather than rendering something half-addressed. It pairs with `strict:` as the other half of one idea: `strict:` refuses a value that's wrong, `required:` refuses one that's missing.

- **A Vocabulary For Unreadable Requests** – `Weft::BadRequest` and its two members (`Weft::InvalidParamValue`, `Weft::MissingParam`) fill the 400 that Weft's error family was missing, and they're matchable like any other: `recovers from: Weft::BadRequest, with: NotFoundPage, status: 404` if you'd rather your app answered differently. The line they draw is worth borrowing: **400 means "I can't read what you sent"; 422 means "I read it fine, and it isn't acceptable."**

- **Typed Values Wherever They Come From** (`type:`/`digest:` on `derives` and `receives`) – A component handed a whole record derives the scalar that names it, and that scalar can now say what it is:

  ```ruby
  receives :driver
  derives(:driver_id, type: :uuid) { |p| p.driver.id }
  identifies_by :driver_id
  ```

  Previously the same UUID kept its dashes through a `param` and lost them through a `derives`, leaving an app carrying two id styles for one kind of value. Identity now asks what a key declares rather than which door declared it. Declaring one key as two different types is refused — one key holds one value.

- **A Component Can Decline A DOM Id** (`anonymous!`) – Chrome that nothing routes to, refreshes, or brings has no use for an id, and an id every instance shares isn't merely useless: ids must be unique in a document, so it's invalid HTML that breaks `getElementById` and every `#id` selector aimed near it. `anonymous!` renders no `id` attribute at all, and joins `identifies_by` and `unique!` as the third mutually exclusive answer — so a chrome base class can decline while the subclasses that *are* addressed declare identity and override it.

- **Weft Tells You When Two Elements Share An Id** – Render the same id twice and Weft says so once per class, naming the class, the id, and the three declarations that answer it. It watches the render rather than the class body on purpose: what makes an id wrong is a second instance appearing, which no class body can predict — a component rendered once per page is right to wear its bare class id.

- **Booleans That Understand Forms** – `type: :boolean` now reads the words browsers and humans actually send — `true/false`, `1/0`, `on/off`, `yes/no`, `t/f`, `y/n`, in any case. A bare `<input type="checkbox">` submits `on` when checked, which previously read as **false**; it now reads as true, which is what it plainly meant.

- **Declared Component Identity** (`identifies_by`) – Name the params that distinguish one instance from the next, and read a class body to find out. Full model in [the DSL reference](docs/dsl.md#identity).
  - `identifies_by :order_id, :line_item_id` – slots appear in the order you write them, and a blank one holds its place rather than shifting the rest
  - The value can arrive through any door — a `param`, a `derives`, a `defines`, or a `receives` — so a component handed a whole record derives the scalar that names it and identifies by that
  - `identifies_by { |params| "cart-#{params.user_id}" }` composes the whole id yourself, for the cases a list of slots can't express
  - An identifying value that isn't a scalar raises `Weft::InvalidIdentifierValue` naming the component and the param, rather than composing a selector two instances could share

- **A Slot For Components With Nothing To Name Them** (`unique!`) – A badge repeated down a table or a card the page renders many of asks for its own slot, and Weft issues it a token at first render and carries it from then on. Uniqueness doesn't publish a route: a component that wants one still declares something that earns it.

- **Digested Identity Slots** (`digest:`) – `param :label, digest: true` renders an identifying value as a short deterministic hash, so values that are blank, long, or not URL-shaped still give each instance a stable target. The same value always yields the same id, across processes and across workers. `digest: 12` widens one param; `Weft.configuration.digest_length` moves the default.

- **UUID Params** (`type: :uuid`) – Declares a param as a UUID string, and keeps its dashes intact where a DOM id would otherwise sanitize them.

- **Collision Detection Covers DOM Ids** – Two components whose ids would collide are caught when routes are validated, alongside the route checks — so a fragment that could only ever land on another component's element is a startup error, not a mystery in the browser.

- **Say Where A Derived Value Belongs** (`contextual:`/`override:` on `derives`) – Two keywords for the cases the default doesn't fit. `contextual: true` makes a value a function of *where it's read*, so each component inheriting it computes its own — right for a label assembled from keys its readers differ on, and it runs once per reader even when nothing changed, so keep those cheap and pure. `override: true` claims the key for one component and everything inside it: "in here, `:user` is the customer being viewed, not the person viewing," computed once, invisible outside that subtree. It outranks an inherited value and nothing else — a wire value still wins, and so does a key a verb block returned.
  - `contextual` implies `override`, since a contextual derivation that deferred to an ancestor could never run; declaring `contextual: true, override: false` is refused rather than quietly ignored

### Bug Fixes:

- **One Derivation, One Answer** – A `derives` block ran once per *component* rather than once per request, so a value an ancestor computed was computed again by anything that hadn't inherited it already — and worse, which of two components' answers you got depended on **where in a parent's `build` the read happened to sit**. Moving one line of rendering code could change both what children saw and how many queries ran. A derivation's outcome now belongs to the derivation: it settles on first read and every component that shares it sees that answer.
  - A failure settles the same way. The same exception is re-raised on every later read and the block doesn't run again, so a lookup that can fail costs one attempt rather than one per reader — and a derivation can no longer disagree with itself inside a single request
  - If you were relying on a component recomputing an inherited derivation for itself, that's `contextual: true` above
  - A derivation that resolves to `nil` now counts as an answer rather than an absence, so a component nested below it inherits the `nil` instead of quietly running its own derivation for that key. Declared defaults still apply as they always did

- **Every Companion Inherits The Same Request** – A companion picks up the params of the component it rides with, rich values included. Two kinds had nothing to pick up from and quietly fell back to the bare wire: the companions a component brings along when it `transfers` away (`brings ShipmentsCard, on: :hand_off`), and the companions on a `dismisses` response, where the component is gone and only they render. Both now inherit the state the request composed — the record your callable already loaded included — which is the lineage their own `brings` block was already reading. Previously they paid for that lookup a second time and could render a thinner value than the block placing them had just read.
  - A companion identified by a value it can now inherit will render a different DOM id than before, since the value reaching it is the declarer's rather than its own fallback

- **Error Renderings Inherit The Request** – A `recovers` block has always been handed the state the request had reached when it broke, but the rendering below it was built from the bare wire. One error fragment could show the block's value beside a freshly recomputed one — two readings of a single request. A recovery target now inherits the bag its block read, with the block's returned keys riding over it. The record your callable had already loaded is there to render from, instead of being fetched a second time in order to report that the first attempt failed. This closes the gap on every recovery Weft performs: a component's, a page's — full document or htmx body fragment — a live stream's push frame, and a failing companion's.
  - Inheriting outranks deriving, exactly as it does for a component nested inside another's build. A recovery target that declares `derives :order` for a key the broken exchange already had will show the inherited value and leave its own derivation unrun; give it a key of its own when it must work the value out regardless
  - Worth knowing: if the derivation that raised is the one your error rendering reads, it raises again. Derivations are lazy, so this only reaches a target whose job is to re-render the very thing that just failed to load

- **A Broken Error Page Reports The Right Error** – When a page's recovery rendering itself raised, Weft reported *that* error and lost the one that actually broke the page — so a bug in your error page hid the bug you were looking for, and the failing page's own `recovers` chain was abandoned on the way. Page recoveries now stop where component recoveries always have: the second failure is logged, and what you're shown is the original.

- **A Hand-Off's Default Reaches Everywhere Its Key Does** – `receives :page_num, default: 1` used to answer only where a call site had run. Weft composes a params bag in places where nothing has been built yet — the top of a request, an action callable, a stream frame — and there the fallback simply wasn't there, so the way to make one work in a `performs` block was to write the `1` a second time as a `defines`. Two copies of one fallback, free to drift. A default now answers wherever its key is read, because a fallback belongs to the class that declared it rather than to the door it sits beside.
  - A hand-off with *no* default genuinely has nowhere to come from in those places, and reading one now raises **`Weft::UnreachableHandoff`** — naming the component, the key, and both ways out — instead of `undefined method 'order' for an instance of Weft::Params`, which named a class you never wrote
  - `Weft::NotReceived` is unchanged and still means the neighbouring thing: a call site that *did* run and left the value out, where the fix is to pass it

- **Declarations Stop Being Silently Ignored** – `receives :order, type: :uuid` used to be accepted and quietly dropped, because `receives` swallowed any keyword it didn't recognise. Unknown keywords now raise, as they always have on `param` and `derives`.

- **Fallback Derivations Stop Nagging** – A component that declares `derives(:order)` *and* gets embedded under something that already supplies the order is doing the right thing: fetch your own when you're rendered standalone, take the ancestor's when you're nested. Weft used to log a warning every time the second half happened — warning about correct code, and suggesting a fix (share one derivation) that's wrong whenever the two deliberately differ, as when a page eager-loads what a card doesn't. It's gone. The overlay warning stays, because a verb block returning a key really does stop your derivation running for that whole request.

### Breaking Changes:

- **A Declared Type Is Now A Promise** – `type:` used to be a parsing hint that quietly did its best: `?page=wombat` on `param :page, type: :integer` rendered **page 0**, and `:float`, `:decimal` and `:boolean` invented `0.0`, `0.0` and `false` the same way. A value the type can't represent is now refused with a `Weft::BadRequest`, so a bad request fails at the request instead of surfacing three screens later as "this page is showing the wrong records."
  - `?page=` — an empty value — now falls to the param's declared default. It's a cleared field, and treating it as a value is how `default: 1` used to render page 0
  - `strict: false` on a param, or `Weft.configuration.strict_params = false` across the app, restores lenient conversion — and lenient means **exactly** [`ActiveModel::Type`](https://api.rubyonrails.org/classes/ActiveModel/Type.html), the behavior a Rails app already has, verified against every ActiveModel from 6.1 to 8.0
  - Values the type *can* read are unchanged, so a request that was already well-formed behaves exactly as before

- **Identity Is Declared, Not Positional** – A component's DOM id no longer derives from whichever param happened to be declared first. Declare `identifies_by` on any component whose instances must be individually addressable; one that declares nothing wears its class id, which is the right answer for a component appearing once per page.
  - This is the change that makes identity survive inheritance: a subclass can now replace its parent's identity outright, which a first-param convention could never express
  - `Weft::Registry::Eligibility` is now `Weft::Addressing`, and a trailing `Component` is stripped from a DOM id exactly as it already was from a route path

- **Component URLs Say What They Are** – `weft_url` is now `weft_component_url`, naming the component's own GET URL rather than leaving "weft url" to be guessed at. `refresh_url` is gone; it existed only because `weft_url` didn't say what it was for.

- **Announcements Have Their Own Word** – The verb that sends an event out to the page is now `announces`, which leaves `trigger:` meaning exactly one thing: the browser event that fires an element's request. htmx spells opposite ends of the same round trip `hx-trigger` and `HX-Trigger`; weft no longer inherits that ambiguity, so you can read a class body and know which direction an event travels.
  - `announces "order-updated", on: :advance` – `on:` filtering, inheritance, and duplicate collapsing all behave as before
  - The class-level reader is `announced_events`
  - The `HX-Trigger` response header, the `trigger:` kwarg, and `refreshes on:` are all untouched

- **Companions Are Brought, Not Included** – The verb that sends a companion along with a response is now `brings`, so a component's class body no longer reads like Ruby's `include` or ActiveRecord's `includes` — and the verb finally matches the word the docs use for what it produces.
  - `brings Oms::OrderHeader, on: :advance` – `on:`, `when:`, and the delta block are unchanged
  - The class-level reader is `companions`

Both are pure renames: no behavior changed, and the wire format is identical.

## v0.2.0 (2026-08-11)

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
