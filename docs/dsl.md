# The Weft DSL

A Weft component describes its interactive behavior in two layers. **Class-body declarations** — the verbs — state what the component does: it refreshes on a timer, it performs an action, it recovers from an error. **Element kwargs**, used inside `build`, wire individual elements to those behaviors: this button performs the `:cancel` action, this div loads a tooltip on hover. Both layers compile down to auto-generated routes and htmx attributes; you write neither by hand. (The HTML itself — the `build` method and everything inside it — is [Arbre](arbre.md), documented separately.)

```ruby
class DeliveryStatus < Weft::Component
  attribute :delivery_id          # wire state

  refreshes every: 5.seconds      # verb: live updates

  performs :cancel do |attrs|     # verb: user-initiated action
    CancelDelivery.call(Delivery.find(attrs.delivery_id))
  end

  def build(attributes = {})
    super
    delivery = Delivery.find(attrs.delivery_id)
    span "Arriving #{delivery.eta.humanize}"
    button "Cancel", action: :cancel    # element kwarg: wires to the verb
  end
end
```

**In this document:**

- [Attributes](#attributes)
- [Verbs](#verbs)
  - [`refreshes` — the client re-fetches](#refreshes--the-client-re-fetches)
  - [`pushes` — the server sends updates](#pushes--the-server-sends-updates)
  - [`performs` — user-initiated actions](#performs--user-initiated-actions) and [the callable contract](#the-callable-contract)
  - [`transfers` — actions that render something else](#transfers--actions-that-render-something-else)
  - [`dismisses` — remove from the DOM](#dismisses--remove-from-the-dom)
  - [`triggers` — announce to the rest of the page](#triggers--announce-to-the-rest-of-the-page)
  - [`includes` — companions in the same response](#includes--companions-in-the-same-response)
  - [`recovers` — declare error behavior](#recovers--declare-error-behavior)
  - [Other class-body declarations](#other-class-body-declarations)
- [Element kwargs](#element-kwargs): [`action:`](#action), [`navigate:`](#navigate), [`loads:`](#loads), [`trigger:`](#trigger), [`push_url:`](#push_url) — plus the [swap](#swap-values), [trigger](#trigger-values), and [target](#targets) value tables
- [Shorthands](#shorthands)

## Attributes

```ruby
attribute :status, default: "active"
attribute :page, default: 1
```

Attributes are a component's *wire state* — the values that identify what this particular instance shows, small enough to travel in a URL. When the component renders inside a page, attributes come from the rendering call (`orders_panel(status: "shipped")`); when it renders over the wire — a refresh, an action, an SSE push — they come from request parameters. Either way, `build` and action callables see the same resolved values.

Wire values arrive as strings, so Weft coerces them based on each attribute's default: an `Integer` default coerces with `to_i`, a `Float` with `to_f`, and a `true`/`false` default maps `"true"` and `"1"` to `true` (anything else to `false`). Attributes with other defaults (strings, `nil`) pass through untouched. A `type:` kwarg is accepted on `attribute` but reserved for future use — today, the default *is* the type declaration.

Inside the component, `attrs` returns the resolved values with method-style access:

```ruby
attrs.status      # => "shipped"
attrs.page        # => 2 (an Integer — coerced)
attrs[:status]    # explicit hash-style access
attrs.to_h        # the underlying hash
```

Declared attribute names always win over hash methods — if you declare `attribute :count`, `attrs.count` is your value, not `Hash#count`. For anything not declared, the hash API is available directly on `attrs`.

Declaring attributes has a routing consequence: a component with attributes (or any verb below) is considered independently addressable and gets its own route. See [Routing](routing.md).

## Verbs

### `refreshes` — the client re-fetches

```ruby
refreshes every: 10.seconds            # poll on a timer
refreshes every: 0.6                   # sub-second polling ("every 600ms")
refreshes on: "order-updated"          # re-fetch when an event fires
refreshes every: 30, on: "saved"       # both
```

The component's wrapper element gets the htmx wiring to GET its own route and replace itself with the response (`outerHTML` swap). With `every:`, that happens on a timer. With `on:`, it happens whenever the named event fires — typically emitted by some other component's `triggers` declaration, arriving as an `HX-Trigger` response header and listened for at the body level, so any component on the page can react to any other's events.

Multiple `refreshes` calls accumulate into a single trigger list. Because the wiring is declared on the class, it's present both in the initial page render *and* in every refreshed fragment — the component keeps refreshing forever, with nothing duplicated by hand.

Intervals count in seconds — an integer, a float, or an ActiveSupport duration. Whole seconds render as htmx's `every 5s`; fractional values render in millisecond syntax (`every 600ms`). One millisecond is the floor: anything smaller is rounded up to `1ms`, with a warning through `Weft.logger`.

### `pushes` — the server sends updates

```ruby
pushes every: 5.seconds
```

Where `refreshes` polls, `pushes` streams: the Router auto-generates an SSE endpoint for the component (at `<component path>/_stream` — see [Routing](routing.md)), and the component renders with the htmx SSE attributes to connect to it. On the declared interval — seconds, fractional or whole, with the same 1ms floor as `refreshes` — the server re-renders the component and pushes the result down the open connection.

A new subscriber receives an immediate snapshot frame, then the regular cadence. Pushed frames swap into the component's *interior* (`innerHTML`) — the wrapper element holds the SSE connection, so it must persist across updates.

Pages include the htmx SSE extension script automatically when any component declares `pushes` (the [`include_sse_ext`](configuration.md#include_sse_ext) setting).

### `performs` — user-initiated actions

```ruby
performs :advance do |attrs|
  order = Oms::Order.find(attrs.order_id)
  Oms::AdvanceOrder.call(order)
end
```

Declares an action: the Router generates a route for it, and elements wire to it with the `action:` kwarg (below). When the request arrives, the callable runs, then the component re-renders and the response replaces it in the page.

The full signature:

```ruby
performs :name, method: :post, swap: :outer_html, target: nil do |attrs| ... end
```

- **`method:`** — the HTTP method (default `:post`). A *named* action routes at `<component path>/<name>`; a *nameless* one (`performs method: :delete do ... end`) routes at the component's own path, distinguished by method. A nameless GET action is special: it intercepts the component's own render route, running the callable before every over-the-wire render.
- **`swap:`** — how the response lands in the DOM (default `:outer_html`, replacing the component). See the [swap table](#swap-values).
- **`target:`** — a CSS selector for where the response lands (default: the component itself, by DOM id).

### The callable contract

Action callables receive one argument — the component's resolved `attrs` — and their return value directs what happens next:

- **`nil`** (or any ignored value): re-render with the original attrs. The common case — the callable did its side effect; the fresh render reflects it.
- **a `Hash`**: merged into the attrs (returned keys win), and the merged set drives the re-render. Use this to change state on the way through: `performs :filter do |attrs| { page: 1 } end`.
- **a `Weft::Redirect`**: navigate away instead of re-rendering. Build one with `Weft.redirect`:

```ruby
performs :create do |attrs|
  order = Oms::CreateOrder.call(attrs.to_h)
  Weft.redirect(OrderDetailPage, order_id: order.id)
end
```

`Weft.redirect` takes a `Weft::Page` subclass plus attrs (interpolated into the page's path pattern), or a plain URL string. The Router handles transport: htmx requests get an `HX-Redirect` header, traditional form submissions get a 302.

If the callable raises, the error walks the component's recovery chain — see [Error handling](error-handling.md).

### `transfers` — actions that render something else

```ruby
transfers :edit, to: EditableOrderHeader do |attrs|
  { mode: "full" }
end
```

Identical to `performs` in signature and contract, except the response renders the `to:` component instead of the declaring one — for actions whose natural result is a different piece of UI (a read-only header becoming an edit form). The merged attrs feed the target component. The target only needs to *render*; it does not need its own route (see [routability vs. render targets](routing.md#routable-vs-render-target)).

### `dismisses` — remove from the DOM

```ruby
dismisses :close                        # no side effects
dismisses :archive do |attrs|           # with side effects
  Item.find(attrs.item_id).archive!
end
```

Sugar for `performs` with `method: :delete, swap: :delete`: on success, the component is removed from the page entirely. The callable, if given, runs for side effects. If it raises, Weft overrides the destructive swap (via `HX-Reswap`) so the error rendering appears where the component was, rather than the element silently vanishing.

### `triggers` — announce to the rest of the page

```ruby
triggers "delivery-completed"
```

Every action response from this component carries the named event in its `HX-Trigger` header. Other components subscribe with `refreshes on: "delivery-completed"` — a decoupled way to say "when this changes, those refresh," without the components knowing about each other. Multiple `triggers` declarations accumulate.

### `includes` — companions in the same response

```ruby
includes Oms::OrderHeader                     # alongside every response
includes Oms::OrderHeader, on: :advance       # only for the :advance action
includes Oms::OrderHeader do |attrs|          # with explicit attr mapping
  { order_id: attrs.order_id, compact: true }
end
```

Sometimes one interaction changes two things: completing a shipment updates the shipment card *and* the order header above it. `includes` declares that relationship — whenever this component responds to an action or pushes an SSE frame, the included component renders too, marked out-of-band (`hx-swap-oob`) so htmx routes it to its own DOM slot by id.

Without a block, the included component resolves its attributes from the same request parameters. With a block, the block receives the primary component's resolved attrs and returns the wire attrs for the included one. With `on:`, the inclusion applies only to that named action (and not to SSE pushes; unfiltered inclusions apply to both).

### `recovers` — declare error behavior

```ruby
recovers from: Weft::Unprocessable do |attrs, error|
  { error_message: error.message }
end
recovers from: Weft::Unauthorized, with: LoginPage
```

Declares how this component or page responds when a render or action raises. `from:` matches by exception class, HTTP status code, status range, or an array of those; `with:` names what renders instead. The gem ships default recoveries, so this is opt-in refinement. The complete model — matching, chain order, auto-injected attributes — is in [Error handling](error-handling.md).

### Other class-body declarations

**`adds_children_to :@ivar`** — generates the standard container pattern: children added from a caller's block go into the named element rather than the wrapper, while the component's own structural elements (built during `build`) land normally.

```ruby
class Card < Weft::Component
  adds_children_to :@body

  def build(attributes = {})
    super
    h2 "Header"                       # structural — goes to the wrapper
    @body = div(class: "card-body")   # caller's block content goes here
  end
end
```

The leading `@` in the symbol is required, as a reminder that *you* must assign that instance variable somewhere in `build` — if `build` finishes without assigning it and a child then arrives, Weft raises a pointed error rather than silently misplacing content. The underlying mechanics (and when to hand-roll instead) are in [Arbre: the HTML layer](arbre.md#receiving-caller-content).

**`abstract!` / `routable!`** — override the class's routing eligibility in either direction. Covered in [Routing](routing.md#abstract-and-routable).

## Element kwargs

Inside `build` (and inside blocks nested under it), any element accepts Weft kwargs alongside its normal HTML attributes. Weft intercepts them at render time and expands them into htmx wiring.

### `action:`

```ruby
button "Advance", action: :advance, class: "btn btn-primary"
```

Wires the element to a declared `performs`/`transfers` action on the nearest enclosing component that declares it. Expands to the full htmx set: the request (`hx-post` etc. to the action's route), the target (the component's own element, unless the action declared `target:`), the swap, and the component's current attrs as the payload (`hx-vals`).

On a `form` element, `action:` additionally emits plain HTML `action` and `method` attributes, so the form still submits without JavaScript — and the field values themselves become the payload:

```ruby
form(action: :create) do
  input(type: "text", name: "customer_name")
  input(type: "submit", value: "Create")
end
```

### `navigate:`

```ruby
button "Next", navigate: { page: attrs.page + 1 }
```

Re-fetches the enclosing component with some of its attrs changed — a GET to the component's own route with the overridden values, replacing the component. This is the idiom for filters, sorting, and pagination: same component, different wire state. Pass `nil` to drop an attr from the URL. Pairs naturally with `push_url:` when the new state should be reflected in the address bar.

### `loads:`

```ruby
button "Show manifest", loads: Logistics::ShipmentManifest,
                        with: { shipment_id: shipment.id },
                        swap: :fill, target: "#detail-pane"
```

Loads a *different* component into a chosen DOM location on click (or whatever `trigger:` you add). `swap:` and `target:` are required — `loads:` is the fully-explicit primitive underneath the [shorthands](#shorthands), which exist to fill those in for common patterns. `with:` supplies the target component's wire attrs; omitted, it defaults to the enclosing component's current attrs.

### `trigger:`

```ruby
div(loads: Preview, with: { id: id }, swap: :fill, target: :self,
    trigger: :visible)
```

Sets when the element's request fires. Accepts the semantic symbols in the [trigger table](#trigger-values) or any raw [htmx trigger string](https://htmx.org/attributes/hx-trigger/) for full control (`"mouseenter once from:closest .card"`). Works standalone or alongside `action:` / `navigate:` / `loads:` / a shorthand.

### `push_url:`

```ruby
button label, action: :filter, push_url: "/orders?status=#{status}"
```

Pushes a URL into the browser's address bar when the request completes, keeping the location shareable and the back button meaningful. Pass the URL string, or `true` to push the request's own URL.

### Swap values

Weft accepts semantic swap names (preferred), the htmx-native names as symbols, or any raw string:

| Semantic | htmx equivalent | Effect |
| --- | --- | --- |
| `:replace` | `outerHTML` | Replace the target element entirely |
| `:fill` | `innerHTML` | Replace the target's contents |
| `:before` | `beforebegin` | Insert before the target |
| `:prepend` | `afterbegin` | Insert at the start of the target |
| `:append` | `beforeend` | Insert at the end of the target |
| `:after` | `afterend` | Insert after the target |
| `:remove` | `delete` | Remove the target |
| `:none` | `none` | Don't swap anything |

### Trigger values

| Semantic | htmx equivalent | Fires… |
| --- | --- | --- |
| `:click` | `click` | on click |
| `:hover` | `mouseenter once` | on first hover |
| `:visible` | `revealed` | when scrolled into view |
| `:input` | `input changed delay:300ms` | as the user types, debounced |

### Targets

Wherever a `target:` is accepted: `:self` targets the element itself, a string is a CSS selector passed through to htmx (including forms like `"closest tr"`), and an Arbre element reference targets that element by its id. In verb declarations (`performs`/`transfers`), only the selector-string form applies — `:self` and element references describe elements, which don't exist yet at class-declaration time.

## Shorthands

Shorthands are named presets over the `loads:` machinery — one kwarg that says what the interaction *is*, with the trigger and swap details baked in:

```ruby
button "▸", inline_expand: Oms::OrderInlineDetail,
            with: { order_id: order.id },
            target: "closest tr"
```

The kwarg's value is the component class to load (`with:` supplies its attrs, same as `loads:`). The gem ships these presets:

| Shorthand | Trigger | Swap | Target | Example |
| --- | --- | --- | --- | --- |
| `tooltip:` | `:hover` | `:fill` | supply `target:` | [Tooltip](examples/tooltip.md) |
| `inline_expand:` | `:click` | `:after` | supply `target:` | [Inline Expansion](examples/inline-expansion.md) |
| `lazy:` | `:visible` | `:fill` | `:self` | [Lazy Loading](examples/lazy-loading.md) |
| `modal:` | `:click` | `:fill` | supply `target:` | [Modal Dialog](examples/modal-dialog.md) |
| `load_more:` | `:click` | `:replace` | `:self` | [Click to Load](examples/click-to-load.md) |
| `infinite_scroll:` | `:visible` | `:after` | supply `target:` | [Infinite Scroll](examples/infinite-scroll.md) |
| `live_search:` | `:input` | `:fill` | supply `target:` | [Active Search](examples/active-search.md) |
| `tabs:` | `:click` | `:fill` | supply `target:` | [Tabs](examples/tabs.md) |
| `retry:` | `:click` | `:replace` | `closest .weft-error` | — |

Where the table says "supply `target:`", the preset has no universally-right answer for where the content lands, so the call site provides it (omitting it raises immediately, with a message saying so). Explicit `swap:` and `target:` kwargs always override the preset.

`retry:` is the odd one out: its value is a **URL string** rather than a component class — the failing component's own GET URL, as injected into error components via the `:retry_url` recovery attribute (see [Error handling](error-handling.md)). Its baked-in target replaces the enclosing `.weft-error` box with the freshly-rendered component:

```ruby
button "Retry", retry: attrs.retry_url
```

### Registering your own

```ruby
Weft.register_shorthand :paginate, trigger: :click, swap: :replace
```

A registration names the preset and provides any of `trigger:`, `swap:`, and `target:`. From then on, `paginate:` works as an element kwarg everywhere — same machinery, your vocabulary. Naming interactions after their intent keeps call sites readable: `button "Next", paginate: OrdersPanel, with: { page: 2 }` says more than the four htmx attributes it expands to.
