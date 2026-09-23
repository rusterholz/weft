# The Weft DSL

A Weft component describes its interactive behavior in two layers. **Class-body declarations** — the verbs — state what the component does: it refreshes on a timer, it performs an action, it recovers from an error. **Element kwargs**, used inside `build`, wire individual elements to those behaviors: this button performs the `:cancel` action, this div loads a tooltip on hover. Both layers compile down to auto-generated routes and htmx params; you write neither by hand. (The HTML itself — the `build` method and everything inside it — is [Arbre](arbre.md), documented separately.)

```ruby
class DeliveryStatus < Weft::Component
  param :delivery_id          # wire state

  refreshes every: 5.seconds      # verb: live updates

  performs :cancel do |params|     # verb: user-initiated action
    CancelDelivery.call(Delivery.find(params.delivery_id))
  end

  def build(attributes = {})
    super
    delivery = Delivery.find(params.delivery_id)
    span "Arriving #{delivery.eta.humanize}"
    button "Cancel", action: :cancel    # element kwarg: wires to the verb
  end
end
```

**In this document:**

- [Params](#params): the different ways data gets into your component on each request (analogous to Rails' `params`).
  - [`param`](#param--wire-state) - path component params, query string params, form data, and POST content; all of which together is called "wire state"
  - [`derives`](#derives--lazy-server-side-derivations) - enriched values that can be determined from the wire state, such as a database model loaded by an ID in the query string
  - [`defines`](#defines--static-values) - a variant of `derives` for when a value is known at load time
  - [`receives`](#receives--caller-hand-offs) - rich values handed straight over by whoever renders the component, such as a database model the caller already has in hand
  - [How These Ways Combine](#how-the-doors-combine) - when and why to use them in combination
  - [Inheritance](#inheritance-and-the-render-tree) - how wire state is made available at each layer when components are composed together
- [Behavioral Verbs](#verbs): the user-facing behaviors that your component exposes or provides.
  - [`performs`](#performs--user-initiated-actions) - user-initiated actions which re-render the component afterwards, like submitting a form
  - [`transfers`](#transfers--actions-that-render-something-else) - a variant of `performs` that replaces this component with another
  - [`dismisses`](#dismisses--remove-from-the-dom) - a variant of `performs` that removes this component from the DOM
  - [`refreshes`](#refreshes--the-client-re-fetches) - re-render this component periodically or on specific **client-side** events
  - [`pushes`](#pushes--the-server-sends-updates) - re-render this component periodically or on specific **server-side** events
  - [`recovers`](#recovers--declare-error-behavior) - what your component should do if it encounters an error
  - [`announces`](#announces--tell-the-rest-of-the-page) - tell the other components on the page that something happened, via a **client-side** event
  - [`brings`](#brings--companions-in-the-same-response) - what other components need to redraw when this one does
  - [The Callable Contract](#the-callable-contract) - how to attach logic to each of these behaviors
  - [Other Class-Body Declarations](#other-class-body-declarations)
- [Element Kwargs](#element-kwargs): how the behaviors get attached to your component's UI elements.
  - [`action:`](#action) - attach any of the actions defined with `performs`, `transfers`, or `dismisses` to any HTML element
  - [`navigate:`](#navigate) - a variant of `action` that needs no declaration: re-fetch this same component with some of its wire state changed, which is the idiom for filtering, sorting, and pagination
  - [`loads:`](#loads) - fetch a *different* component and place it somewhere on the page, such as a detail pane that fills in when a row is clicked
  - [Interaction vs. Modifier Kwargs](#the-kwarg-rules)
  - And the modifiers themselves:
    - [`trigger:`](#trigger) - which browser event fires the request, when the default (usually a click) isn't the one you want
    - [`push_url:`](#push_url) - update the browser's address bar when the request completes, so the new state is shareable and the back button still means something
    - [`confirm:`](#confirm) - ask for confirmation in a browser dialog first, and make no request at all if the answer is no
    - [`swap:`](#swap-values) - how the response lands in the DOM: replacing the target, filling it, or inserting around it
    - [`target:`](#targets) - which element the response lands in, for the times it shouldn't be the component itself
  - Kwarg [Presets](#presets) - named groups of settings which let you reuse a common or custom behavior across your whole app

## Params

A component's inputs all reach it through `params`, and there are four ways to declare them — four *doors* into the same bag, each suited to a different kind of value:

- **[`param`](#param--wire-state)** — wire state: values small enough to travel in a URL (an id, a page number, a filter).
- **[`derives`](#derives--lazy-server-side-derivations)** — lazy server-side derivations: values the component works out for itself, on demand.
- **[`defines`](#defines--static-values)** — static values a subclass pins; sugar over `derives`.
- **[`receives`](#receives--caller-hand-offs)** — caller hand-offs: rich objects a call site already holds and passes straight in (a record, a computed collection).

Whichever door a value comes through, you read it the same way — `params.name`, or `params[:name]`. Every verb block sees the same doors `build` does, with one structural exception: `receives` values come from a *call site*, and an action arriving over the wire has no caller, so a callable can't see them. (Need one in an action? Give the key a second door — a `param` or a `defines` — and it stands on its own.) For the bigger picture — how params travel in from a request, down the render tree, and back out into the next refresh or action — see [How params flow](params.md).

### `param` — wire state

```ruby
param :status, default: "active"
param :page, default: 1, type: :integer
```

Params are a component's *wire state* — the values that identify what this particular instance shows, small enough to travel in a URL. They come from the request: query, path, and body values. When the component renders inside a page, it reads the same wire params the page does (see [Inheritance and the render tree](#inheritance-and-the-render-tree)); when it renders over the wire — a refresh, an action, an SSE push — they come from that request's parameters.

Wire values arrive as strings, so a param that means something else declares its `type:`, and Weft coerces the wire value on the way in:

```ruby
param :page, type: :integer     # "2"     → 2
param :rate, type: :float       # "3.14"  → 3.14
param :price, type: :decimal    # "19.99" → BigDecimal("19.99") — full precision, right for money
param :active, type: :boolean   # true/false, 1/0, on/off, yes/no, t/f, y/n — any case
param :zip, type: :string       # looks numeric, isn't — leading zeros survive
param :order_id, type: :uuid    # a string, and one that keeps its dashes in a DOM id
```

An untyped param accepts whatever arrives, uncoerced — right for values that are already strings, and for rich shapes like the nested hash browsers submit for `items[widget]=2`. Declare `type: :boolean` on every flag param: without it, a wire `"false"` is just a truthy string. `default:` is independent of `type:` — the default fills the key when no source supplies a value, is never itself coerced, and must already be an instance of the declared type. Weft checks declarations on the spot: an unknown type or a disagreeing default raises `Weft::InvalidDefinition` at class-load time, not mid-request.

An empty wire value is absence, not a value: `?page=` is a cleared field, so the key falls to its declared default rather than coercing to zero.

#### `strict:` — what a type guarantees

A declared type is a promise about the values a param will hold, and Weft keeps it: a wire value the type cannot represent is **refused**, not coerced into something invented.

```ruby
param :page, type: :integer
```

`?page=wombat` raises `Weft::InvalidParamValue` — a `Weft::BadRequest`, so it answers **400** and matches `recovers from: Weft::BadRequest`. The error carries every violation from that request, each naming the key, the raw value exactly as it arrived, and what the type wanted. That raw value is the point: an error component redrawing a form needs to put `wombat` back in the box, which the coerced-away `0` could never do.

Strictness is on by default and turns off per param, or globally via [`Weft.configuration.strict_params`](configuration.md#params):

```ruby
param :page, type: :integer, strict: false   # coerce leniently instead
```

With strictness off, coercion is exactly [`ActiveModel::Type`](https://api.rubyonrails.org/classes/ActiveModel/Type.html)'s — the behavior a Rails application already has, warts and all. Note one consequence worth knowing before you reach for it: ActiveModel's boolean has a closed *false* list and treats everything else as true, so `?flag=wombat` is `true` there where strict mode refuses it, and `?flag=no` is `true` there where strict mode reads `false`.

#### `required:` — refusing absence

`strict:` refuses a malformed value; `required:` refuses a missing one. They are separate questions and compose:

```ruby
param :order_id, type: :uuid, required: true
```

If no source supplies `order_id`, Weft raises `Weft::MissingParam` — also a `Weft::BadRequest`, also 400. A required param may not declare a `default:`, since a default *is* the answer to absence; declaring both raises `Weft::InvalidDefinition` at class-load time.

Note the two doors default opposite ways, and deliberately: a `param` is optional until you say `required: true`, because the wire is absent by nature, while a [`receives`](#receives--caller-hand-offs) is required until you give it a `default:`, because a hand-off is the call site's contract.

Inside the component, `params` returns the resolved values with method-style access:

```ruby
params.status      # => "shipped"
params.page        # => 2 (an Integer — coerced)
params[:status]    # explicit hash-style access
params.to_h        # the underlying hash
```

Declared param names always win over hash methods — if you declare `param :count`, `params.count` is your value, not `Hash#count`. For anything not declared, the hash API is available directly on `params`.

Only a component's *own* declared params serialize — into its refresh and stream URLs and its action payloads. That's the refresh contract: a standalone request must be able to reconstruct the component from its URL, so only URL-safe wire state belongs there. The other three doors are server-side and never serialize.

Params are also where a component's DOM identity usually comes from — but nothing here is implicit: you say which ones with [`identifies_by`](#identity), below.

Declaring a param has a routing consequence: a component with params (or any verb below) is considered independently addressable and gets its own route. See [Routing](routing.md).

### `derives` — lazy server-side derivations

```ruby
derives(:order) { |params| Oms::Order.find(params.order_id) }
```

A derivation is a value the component computes for itself — the replacement for the find-by-id dance at the top of every `build`. Declaring one registers the block; it runs **at most once per request**, when `params.order` is first read, and **never runs if nothing reads it**. The outcome settles there and then: whatever the block returned is the answer everywhere that derivation reaches, for the rest of the request.

Derivations chain lazily. A block that reads another derived key forces it on demand:

```ruby
derives(:order)     { |p| Oms::Order.find(p.order_id) }
derives(:shipments) { |p| Logistics::Shipment.for_order(p.order.id) }
```

Reading `params.shipments` forces `shipments`, which reads `params.order` and forces that in turn — so a render computes exactly what it touches and nothing more. Derived values are server-side (never serialized, not routable-making), but they do flow down the render tree like everything else in the bag, and a value an ancestor already computed is not recomputed by a child.

**The block is a `(params) -> value` pure function.** It runs against a sandboxed `self`: `params` and lexical constants are in reach, and `Kernel` stays available (`raise`, `format`, `Integer()`), but nothing component-specific is — a bare method call raises `NameError`, which keeps a derivation portable and side-effect-free. Each block runs in its own fresh, disposable context, so scratch instance variables are allowed but never outlive the one execution. If the derivation belongs to a service, call it explicitly: `derives(:report) { |p| ReportService.call(p.account_id) }`.

A failing derivation raises at *first read* — which lands inside the `recovers`-wrapped render, so `recovers from: ActiveRecord::RecordNotFound` and friends handle it the same way they handle a failure in `build`. A derivation nobody reads never raises. A failure settles like any other outcome: the same exception is raised again on every later read, and the block does not run a second time. A lookup that can fail costs you one attempt, not one per reader.

#### Whose value is it?

By default a derivation belongs to the class that declares it. Compute it once, and everything rendered inside that component sees that value — including a component that declares the same key for itself. That's the fallback idiom: declare `derives(:order)` so you work when rendered standalone, and inherit the richer value when you're nested inside something that already has one.

Two keywords change that, and both are opt-in:

```ruby
derives(:label, contextual: true) { |p| "#{p.count} of #{p.total}" }
derives(:user, override: true)    { |p| Customer.find(p.customer_id) }
```

**`contextual: true`** makes the value a function of *where it is read* rather than something the declaring class owns. Every component inheriting it computes its own, so a derivation that reads a key its readers differ on gives each of them the right answer. The cost is real: it runs once per reader, **even when nothing it reads has changed**. Keep contextual derivations cheap and pure — nothing expensive, nothing that can disagree with itself between runs, nothing with side effects.

**`override: true`** claims the key for this component and everything it contains, against an ancestor that also supplies it. It's how you say "inside here, `:user` means the customer being viewed, not the person viewing" — computed once, seen throughout that subtree, and invisible outside it. It lifts the derivation above the *inherited* value only: a wire value still wins, and so does a key returned by a verb block.

`contextual` implies `override` — a contextual derivation that deferred to an ancestor could never run at all — so `contextual: true, override: false` is refused rather than silently ignored.

`params.to_h` and most delegated Hash-API calls materialize every remaining derivation first — the eager escape hatch when you genuinely want the whole bag. That is inherent: they promise every value, so every derivation has to run, and one that raises takes the whole call with it.

Two are answered without that. `params.keys` reads the declarations, so it costs nothing and works even when a derivation has already failed; a thunk occupies its key whether or not it has run. `params.any?` forces one key at a time and stops at the first match, so a satisfied `any?` never pays for the rest of the bag.

And as everywhere else, a declaration wins: declare `param :keys` and `params.keys` is your value, not the bag's key list.

### `defines` — static values

```ruby
defines label: "Drivers", accent: "available"
```

`defines` is sugar for statically-known derivations: each pair registers `derives(key) { value }`, with the value fixed at declaration. It shines in a subclass that pins constant faces of an inherited component while deriving the dynamic ones:

```ruby
class StatCard < Weft::Component
  builder_method :stat_card
  param :status
end

class AvailableDriversCard < StatCard
  defines label: "Drivers", accent: "available"          # fixed
  derives(:value) { |_p| "#{Driver.available.count}/#{Driver.count}" }  # per render
end
```

The catch is in the name: the values are fixed **when the class body runs**, not per render. Anything computed (a query, a count, a clock) must stay in `derives`, because an interpolated value here would freeze at load time. If it isn't a literal constant, it's a `derives`.

**A pin claims its key.** This is the one place `defines` and `derives` part company. A derivation *yields*: it is a fallback for standing alone, so a value supplied from above wins when you're nested. A pin is the opposite claim, and it has to be, because what makes `defines` worth writing instead of a plain Ruby constant is fixing a value that something above you also supplies. So it beats an inherited value, for this class and everything it contains. It still loses to the component's own wire param, exactly as a derivation does.

**What you read back is Weft's own frozen copy.** One pin is one object, shared by every instance of that class for the life of the process, so a mutable value would carry one render's changes into every later request. Weft copies what you hand it and freezes the copy: your object is never touched, and `params.nav << "late"` raises `FrozenError` on the line that tried it instead of quietly poisoning the next request. Two edges worth knowing. The freeze is shallow, so `defines nav: [{ n: 1 }]` still shares that inner hash. And a `Class` or `Module` is passed through as itself, because copying one yields something that is no longer the class you named.

**`defines` takes no keyword options**, and that is a statement rather than an omission. `type:` and `digest:` describe what a value is and how it should render into an id; a pin has answered both already, since you handed over the final value, in the class you wanted, identical on every instance. Because the pairs are a bare hash, a keyword written beside them becomes an ordinary key rather than being refused the way `param` and `derives` refuse one, so `defines label: "x", digest: true` declares a key called `digest`. Weft warns when a key both carries a facet's name and holds a value that facet would have accepted, and stays quiet otherwise: `defines type: "premium"` is a perfectly good key named `type`.

### `receives` — caller hand-offs

```ruby
receives :order
receives :page_num, default: 1
```

Some values can't ride a URL — an `ActiveRecord` object, a pre-built collection, anything rich. `receives` declares that a call site hands the value over directly: given an `OrderRow` that declares `builder_method :order_row`, a parent building `order_row(order: order)` fills `params.order` for the code inside `OrderRow`. The kwarg is consumed as the hand-off, so it never becomes an HTML attribute on the wrapper, and the value never serializes into a URL.

A hand-off is **required by default**: a call site that omits it raises `Weft::NotReceived`, with the backtrace pointing at the call site rather than deep inside the framework. Declaring a default makes it optional — `receives :page_num, default: 1`, and an explicit `default: nil` counts too (the presence of the keyword is what makes it optional, not the value).

That default reaches further than the call site. Weft composes a params bag in places where nothing has been built yet — the top of a request, an action callable, a stream frame — and there the hand-off door doesn't exist at all, because no caller ran. A declared default answers anyway: a fallback belongs to the class that declared it, not to the door it sits beside, so `receives :page_num, default: 1` reads as `1` in a `performs` block without the `1` being written a second time as a `defines`. A hand-off with **no** default has nowhere to come from in those places, and reading it raises **`Weft::UnreachableHandoff`** — which names the key and says both ways out, rather than the bare `NoMethodError` an unnamed absence would give you. `Weft::NotReceived` is the neighboring failure and a different one: there a call site *did* run and left the value out, so the fix is to pass it.

Hand-offs are server-side: declaring one doesn't make a component routable, since there's no way to reconstruct an `Order` from a URL. A component that lives only inside a parent — always handed its data, never served standalone — can say so with **`dependent!`** (an alias of [`abstract!`](routing.md)): "my parent passes this in every time; serving me on my own makes no sense."

If a component *is* routable and declares a required hand-off with no wire counterpart, Weft warns at route validation — such a component renders fine embedded but would raise `Weft::NotReceived` on every standalone refresh. Give it a wire dual (below) or mark it `dependent!`.

### How the doors combine

A key can have more than one door, and Weft resolves the value from a fixed order of sources. Highest wins; `nil` at any level falls through to the next:

1. a **received** hand-off (`receives`)
2. a **request overlay** — a hash returned from a verb block earlier in this request (an action callable, a `transfers` or `brings` block, a `recovers` adjustment). An overlay entry speaks *as* the wire for its key: its value replaces the wire's — including rich objects, which pre-empt a matching `derives` so nothing refetches what the request already loaded — and an explicit `nil` *clears*, masking the wire so resolution falls below it
3. the component's **own wire** value (`param`)
4. an **inherited** value — from an ancestor in the render tree, or from whatever the request had already composed by the time this component rendered
5. the component's **own derivation** (`derives` / `defines`)
6. the component's **own declared default**

One declaration moves within that order: a `defines`, and a `derives` written `override: true`, sit *above* the inherited value rather than below it. That is what lets a subclass pin a value the page around it also supplies.

The first five are values the bag *holds*. The sixth is a fallback the bag *asks for* when a read finds nothing, and that difference shows at every boundary: a default belongs to the class that declared it and never travels, so a nested child — or the target of a `transfers` — falls back to its own, not to the one above it.

That order is what makes *duals* work — declaring a key through two doors so it resolves whether it's handed over or has to fetch itself:

- **`param` + `receives`** — handed the value when embedded (no query round-trip), wire-borne when rendered standalone, so a self-refreshing card embedded with `stat_card(status: "hot")` keeps its status across refreshes.
- **`derives` + `receives`** — handed the value when embedded, self-fetching when standalone. A `derives` dual also satisfies the refresh-safety lint.
- **`param` + `derives`** — use the wire value if present, otherwise derive one.

A derivation that doesn't run is the ordinary case, not a problem. Declare one on a component that also gets embedded, and it stays quiet while an ancestor supplies the key — then fires when the same component answers its own refresh. That's the point of writing it: **take the value from above when you're nested, fetch your own when you're standalone.** It costs nothing when it's shadowed, because an unrun derivation is a block nobody called.

The one case Weft mentions is an **overlay**: a verb block earlier in this request returned the key, so it outranks your derivation and supplied what yours would have. Logged once per class and key — not an error, and often just what you meant, but the two sources sit far apart in the code and a `derives` that stopped running is easier to hear about than to notice.

### Inheritance and the render tree

Within one render, each component starts from a copy of its nearest ancestor component's (or page's) resolved params: it sees everything *above* it in the tree, nothing *beside* it. A bare `shipments_card` embedded in a page that declares `param :order_id` reads `params.order_id` without declaring anything itself.

One thing does *not* travel down: declared **defaults** stay with the class that declared them, so a child with `param :view, default: "open"` inside a parent with `param :view, default: "all"` shows `open`. A fallback is a private answer to "nobody told me," not an opinion to broadcast. Everything else rides, including values an ancestor's derivation already computed: a derivation forced above you is a value by the time you inherit it, so nothing refetches.

**A hand-off rides too, and it keeps its place at the top of the order.** Take a `StatusCard` that declares `builder_method :status_card` and `receives :status`, rendering inside itself a `StatusBadge` that declares `builder_method :status_badge` and a `param :status` of its own. Build the card with `status_card(status: "shipped")` and everything it renders inside sees that status: the badge reads `shipped` even when the page's URL carries `?status=archived`. What the call site said expressly about this card wins over what the page happened to be filtered by.

That is what makes a collection work. A row rendering four of those cards from four statuses gives each card's badge its own value, so four badges show four statuses and claim four DOM ids, rather than all four reading the page's filter and colliding on one id that only one of them could be swapped into.

The nearest call site wins, per key. If the card itself builds `status_badge(status: "archived")`, the badge reads `archived`, and keys nobody nearer mentioned keep the card's value. For that the badge needs `receives :status` alongside its `param`: a kwarg naming a key the component declares any other way renders as an HTML attribute instead, and says so in the log. Passing `nil` steps aside instead of overriding, clearing the inherited hand-off so the badge resolves its own wire value.

Two shapes of consumption both work, and both are idiomatic:

- **Declare-and-read.** The component declares the keys it consumes (through whichever door fits) and reads them. Self-documenting; the declaration is a contract. Most components want this.
- **Inherit-and-read.** A base component reads `params.order_id` that it never declares, trusting the render tree — or a subclass — to supply it. This keeps the base pipeline-agnostic: each subclass chooses its own door (`param`, `receives`, or `derives`) to fill the key, and the shared `build` stays the same. The cost is that the dependency is implicit — nothing in the base names what it needs.

Subclasses can also **redeclare** an inherited key. Redeclaring through the *same* door overrides the parent's declaration (the block or metadata is replaced, keeping the parent's declaration-order position). Redeclaring through a *different* door adds a dual — it doesn't replace the parent's door. There's no way to *un*-declare a key a parent declared; a subclass that needs different behavior overrides or duals, it doesn't remove.

## Identity

Every rendered component wears a DOM id, and Weft addresses fragments by it: `#order-row-42` is how a refresh knows what to replace and how an out-of-band swap finds its slot. An id is composed from the class name — its **stem** — and whatever you nominate to distinguish one instance from the next.

```ruby
class OrderRow < Weft::Component
  param :order_id
  identifies_by :order_id        # id="order-row-42"
end
```

Two consequences are worth holding onto. Sibling instances that resolve to the *same* id are only individually addressable by accident — the first one wins. And because a [`brings`](#brings--companions-in-the-same-response) companion is addressed by id, identity decides which companions can **coexist in one response**: two that resolve to the same id collide, and only one rides.

### `identifies_by` — name what distinguishes an instance

Pass the params that identify the component, in the order they should appear:

```ruby
identifies_by :order_id, :line_item_id   # id="line-item-row-42-7"
```

Order is the order you write, not the order the params were declared in. Each value is sanitised so the single `-` between slots stays unambiguous — a dash inside a value becomes an underscore — and declared positions are never collapsed, so a blank slot still occupies its place rather than shifting the ones after it.

The value may come through **any door**: a `param`, a `derives`, a `defines`, or a `receives`. What matters is the value's *type*, not where it entered from. That makes a derivation the natural answer when a component is handed a whole record:

```ruby
class DriverRow < Weft::Component
  receives :driver                                   # the record cannot compose an id
  derives(:driver_id, type: :uuid) { |p| p.driver.id }  # the scalar that names it can
  identifies_by :driver_id
end
```

`type:` and `digest:` are declarable on `derives` and `receives` as well as on `param`, and mean the same thing at each door — so the UUID above keeps its dashes exactly as `param :driver_id, type: :uuid` would, rather than an app carrying two id styles for one kind of value. Weft can do less about them on the server-side doors, since a hand-off or a derivation is already a Ruby object with nothing to coerce: there they say what the value *is*, for the places Weft consults a type. A key declared through two doors may not be given two different types — one key holds one value, so that's refused rather than resolved by precedence.

`defines` takes neither, on purpose: its value is fixed at class-load time, so it is already whatever you wrote. (And a `defines` value can't distinguish instances — every one of them shares it — so identifying by one is a sign the component wants a different identifier.)

An identifying value must be a **scalar** — a String, Symbol, number, boolean, or `nil`. Anything else raises `Weft::InvalidIdentifierValue` naming the component and the param, because an Array or a Hash would otherwise stringify into a selector two instances could share, and a record's default `to_s` carries its memory address, which changes on every request.

`nil` and `""` are legitimate: both render an empty slot, so `id="order-row-"`. Weft warns once per class and param when that happens, since every instance with a blank value lands on the same id — see `digest:` below for the usual fix.

**A block form** composes the whole id yourself, for the cases a list of slots can't express:

```ruby
identifies_by { |params| "cart-#{params.user_id}" }
```

The block receives the params bag and returns the **entire id** — the stem is not prefixed for you, so include whatever you want in it. It runs sandboxed against the bag rather than the instance, which is what lets Weft answer "what id would this class wear?" without building one. Deliberate collisions are allowed here — two components sharing an id so one swaps over the other is a fair reason to reach for this — but an id Weft cannot target is refused rather than rendered.

### `unique!` — a slot for a component with nothing to name it

Some components have nothing to identify by and still need their own slot: a badge repeated down a table, a card the page renders many of. `unique!` has Weft issue a token at first render and carry it from then on:

```ruby
class StatusBadge < Weft::Component
  unique!                        # id="status-badge-M3f9c1a20"
end
```

It is an alternative to `identifies_by`, not a companion to it — declaring both raises, since they are contradictory claims rather than a precedence puzzle. Like `identifies_by`, it replaces any identity inherited from a superclass. Asking for a slot does not publish a route: a component that wants one declares something that earns it, or says `routable!`.

### `anonymous!` — for a component nothing addresses

The third answer, and the right one for chrome: a card, a tooltip, a wrapper that a page renders many of, where nothing routes to, refreshes, pushes to, or brings any of them.

```ruby
class Card < Weft::Component
  anonymous!                     # renders no id attribute at all
end
```

An id every instance shares isn't merely useless — ids must be unique within a document, so it's **invalid HTML**, and it breaks `getElementById` and every `#id` selector aimed near it. `anonymous!` renders no `id` attribute at all rather than an empty one.

It's the third of three mutually exclusive declarations, alongside `identifies_by` and `unique!`: declaring any of them replaces whichever an ancestor declared. So a chrome base class can be anonymous while the subclasses that *are* addressed say so — and they must, since a component that gets `brings` along is swapped by DOM id.

Declaring it alongside `pushes` raises when routes are validated: a stream swaps by DOM id, so an anonymous component has nowhere for its pushes to land. `refreshes` is fine — it re-renders itself positionally, with no `hx-target`.

**Weft never infers this.** What makes an id wrong is rendering more than one instance on a page, which is a property of the *render*, not of the class — two classes can declare identically and want opposite answers. A component that declares nothing keeps its bare class id, which is exactly right for one that appears once per page. What Weft does instead is *observe*: render the same id twice and it says so once, naming the class and these three verbs.

### `digest:` — when the values collide but the instances differ

An identifying param whose values are often blank, very long, or not URL-shaped can render its value as a short hash instead:

```ruby
param :label, digest: true       # id="tag-D2a6c3f05"
param :label, digest: 12         # a longer digest, for a crowded page
```

The digest is deterministic — the same value always yields the same id, across processes and across workers — so it stays a stable target between requests. It's all-or-nothing per param rather than a fallback: a digested param is *always* digested, so its id doesn't change shape depending on what the value happens to be. `Weft.configuration.digest_length` sets the default width for declarations that don't name one.

### What identity is not

A DOM id is a **label, not a carrier**. Every value it derives from travels on the wire independently, so nothing is lost when an id is opaque, and nothing is transported by making it descriptive. Two components whose ids would collide by class name are caught when routes are validated — see [Collision detection](routing.md#collision-detection).

## Verbs

Verbs are **class-body declarations**: they state what a component *does* — once, at the class level, the way `param` and its siblings declare what it *consumes*. The other layer, [element kwargs](#element-kwargs), wires individual elements to these behaviors from inside `build`; a `performs` declared here is inert until some element carries `action:` naming it (forms and buttons usually).

### `performs` — user-initiated actions

```ruby
performs :advance do |params|
  order = Oms::Order.find(params.order_id)
  Oms::AdvanceOrder.call(order)
end
```

Declares an action: the Router generates a route for it, and elements wire to it with the `action:` kwarg (below). When the request arrives, [the callable](#the-callable-contract) runs, then the component re-renders and the response replaces it in the page.

The full signature:

```ruby
performs :name, method: :post, swap: :outer_html, target: nil do |params| ... end
```

- **`method:`** — the HTTP method (default `:post`). A *named* action routes at `<component path>/<name>`; a *nameless* one (`performs method: :delete do ... end`) routes at the component's own path, distinguished by method. A nameless GET action is special: it intercepts the component's own render route, running the callable before every over-the-wire render.
- **`swap:`** — how the response lands in the DOM (default `:outer_html`, replacing the component). See the [swap table](#swap-values).
- **`target:`** — a CSS selector for where the response lands (default: the component itself, by DOM id).

### `transfers` — actions that render something else

```ruby
transfers :edit, to: EditableOrderHeader do |params|
  { mode: "full" }
end
```

Identical to `performs` in signature and [contract](#the-callable-contract), except the response renders the `to:` component instead of the declaring one — for actions whose natural result is a different piece of UI (a read-only header becoming an edit form). The returned hash overlays the request for the target's render: override its wire values, or hand it rich objects that pre-empt its own `derives`.

The target inherits the state the request has composed, exactly as a nested child inherits its parent's — so a record the callable loaded is already there and needn't be handed over. Its own **defaults** stay sovereign (they don't travel), and it's the *target's* [`brings`](#brings--companions-in-the-same-response) companions that ride the response: after the swap, the target is the component in charge. To override something it inherited, return the key; an explicit `nil` clears it. The target only needs to *render*; it does not need its own route (see [routability vs. render targets](routing.md#routable-vs-render-target)).

### `dismisses` — remove from the DOM

```ruby
dismisses :close                        # no side effects
dismisses :archive do |params|           # with side effects
  Item.find(params.item_id).archive!
end
```

Sugar for `performs` with `method: :delete, swap: :delete`: on success, the component is removed from the page entirely. The callable, if given, runs for side effects, and the success response carries no body — htmx removes the element on its own, and Weft never re-renders a component whose record was just deleted, so `build` needs no guard against the vanished state. Out-of-band [`brings`](#brings--companions-in-the-same-response) companions still ride the response, and inherit the state the request composed: nothing of yours rendered for them to branch from, but the work your callable did still reaches them. Like `performs`, it accepts a `target:` for the occasional removal that should land elsewhere.

If the callable raises, Weft overrides the destructive swap (via `HX-Reswap`) so the error rendering appears where the component was, rather than the element silently vanishing — and the error fragment [adopts the component's own tag](error-handling.md#auto-injected-recovery-params), so a failed row delete produces an error `<tr>`, not a `<div>` wedged into a table.

### `refreshes` — the client re-fetches

```ruby
refreshes every: 10.seconds            # poll on a timer
refreshes every: 0.6                   # sub-second polling ("every 600ms")
refreshes on: "order-updated"          # re-fetch when an event fires
refreshes every: 30, on: "saved"       # both
```

The component's wrapper element gets the htmx wiring to GET its own route and replace itself with the response (`outerHTML` swap). With `every:`, that happens on a timer. With `on:`, it happens whenever the named event fires — typically emitted by some other component's `announces` declaration, arriving as an `HX-Trigger` response header and listened for at the body level, so any component on the page can react to any other's events.

Multiple `refreshes` calls accumulate into a single trigger list. Because the wiring is declared on the class, it's present both in the initial page render *and* in every refreshed fragment — the component keeps refreshing forever, with nothing duplicated by hand.

Intervals count in seconds — an integer, a float, or an ActiveSupport duration. Whole seconds render as htmx's `every 5s`; fractional values render in millisecond syntax (`every 600ms`). One millisecond is the floor: anything smaller is rounded up to `1ms`, with a warning through `Weft.logger`.

### `pushes` — the server sends updates

```ruby
pushes every: 5.seconds
pushes every: 5.seconds, attempts: 5      # custom failure budget
pushes every: 5.seconds, immediate: false # wait one interval before the first frame
```

Where `refreshes` polls, `pushes` streams: the Router auto-generates an SSE endpoint for the component (at `<component path>/_stream` — see [Routing](routing.md)), and the component renders with the htmx SSE params to connect to it. On the declared interval — seconds, fractional or whole, with the same 1ms floor as `refreshes` — the server re-renders the component and pushes the result down the open connection.

A new subscriber receives an immediate snapshot frame, then the regular cadence. When that snapshot would mislead — the component renders expensive state that's only computed on the push cycle, say — `immediate: false` opts into polling-cadence semantics instead: the first frame arrives after one full interval. Pushed frames swap into the component's *interior* (`innerHTML`) — the wrapper element holds the SSE connection, so it must persist across updates.

A failing push walks the component's [`recovers` chain](error-handling.md#error-handling-on-live-streams) and delivers the recovery component's content as the frame, so a live card shows a visible error state instead of silently going stale. A stream that fails `attempts:` times in a row (default: the [`push_attempts`](configuration.md#push_attempts) setting, 3) pushes a final frame, tells the browser to stop reconnecting, and closes — a durably broken component costs a bounded number of attempts, and the `reopen_stream:` preset gives users a one-click way back in.

Pages include the htmx SSE extension script automatically when any component declares `pushes` (the [`include_sse_ext`](configuration.md#include_sse_ext) setting).

### `recovers` — declare error behavior

```ruby
recovers from: Weft::Unprocessable do |params, error|
  { error_message: error.message }
end
recovers from: Weft::Unauthorized, with: LoginPage
recovers from: ActiveRecord::RecordNotFound, with: NotFoundPage, status: 404
```

Declares how this component or page responds when a render or action raises. `from:` matches by exception class, HTTP status code, status range, or an array of those; `with:` names what renders instead; `status:` declares what a non-Weft error means on the wire, so your app's own exceptions recover with honest semantics (the branded 404 above). The gem ships default recoveries, so this is opt-in refinement. The complete model — matching, chain order, auto-injected params — is in [Error handling](error-handling.md).

### `announces` — tell the rest of the page

```ruby
announces "delivery-completed"                # every action
announces "order-updated", on: :advance       # that action only — arrays too
```

Every action response from this component carries the named event in its `HX-Trigger` header. Other components subscribe with `refreshes on: "delivery-completed"` — a decoupled way to say "when this changes, those refresh," without the components knowing about each other. Multiple `announces` declarations accumulate.

`on:` maps an event to the actions it belongs to. Without it, an event is welded to *every* action the component has — fine when there's one, rarely what a component with several means. A header that both advances an order and hands the region over to an editor would otherwise announce a status change when someone merely clicked Edit, and every subscriber would refetch for nothing. Naming the action keeps the two apart:

```ruby
announces "order-updated", on: :advance   # the status machine ran
announces "order-editing", on: :edit      # responsibility handed to the editor
```

There is deliberately no `when:` counterpart, though [`brings`](#brings--companions-in-the-same-response) has one. An announcement reports what a *callable* did, so a render-context filter has nothing to say about it: "fire when I render as a transfer target" describes a render that ran no callable, and "fire when I transfer away" is already `on: :that_action`.

Events follow the *action*, not the rendering: on a [`transfers`](#transfers--actions-that-render-something-else) response the declaring component's events fire — its callable is what ran — while the target's own events wait for the target's own actions. (The same rule is why a `dismisses` response, which renders no body at all, still announces.)

### `brings` — companions in the same response

```ruby
brings Oms::OrderHeader                       # alongside every response
brings Oms::OrderHeader, on: :advance         # own action(s) only — arrays too
brings Oms::OrderHeader, when: :transferred   # only as a transfer target
brings Oms::OrderHeader do |params|            # adjust this companion's params
  { order_id: params.order_id, compact: true }
end
```

Sometimes one interaction changes two things: completing a shipment updates the shipment card *and* the order header above it. `brings` declares that relationship — when this component renders a response, the companion renders too, marked out-of-band (`hx-swap-oob`) so htmx routes it to its own DOM slot by id.

A companion is an **OOB-delivered child**: it renders against the same request, and it inherits the primary's params exactly as a child built inside the primary's `build` would — rich values included, so an `Order` the primary already derived is shared, not fetched once per companion. The block, if given, receives the primary's params and returns a *delta* overlaid on that picture for this companion alone (an explicit `nil` clears a value; one companion's delta is invisible to the next). Blockless is simply an empty delta.

Unfiltered companions ride every response the component renders in: its own action responses, its SSE pushes, and its arrivals as a [`transfers`](#transfers--actions-that-render-something-else) target. Filters enumerate contexts, and declaring both is a union — either fires:

- **`on:`** names this component's **own** actions (a symbol or an array). It never matches another component's action names — an action arriving via transfer isn't consulted — and it doesn't apply to pushes. Note that `on:` *replaces* the unfiltered default rather than narrowing it, which is why naming your own [`transfers`](#transfers--actions-that-render-something-else) action works: the companion rides that response even though the target, not you, is what renders. Your *unfiltered* companions stay home on a transfer, since "every response I render in" is false when you don't render. A companion riding that way inherits **your** params rather than the target's — the state the request composed for you, with your callable's return laid on top, which is the same picture its block is handed. Nothing of yours rendered, but the request still did that work, so a record your callable loaded reaches the companion already loaded.
- **`when: :transferred`** fires only when this component renders as a transfer target: for companions that should ride the arrival, not every response.

**One slot, one fragment.** An out-of-band swap is addressed by DOM id, so two companions resolving to the same id can't both land — the second would swap straight over the first. Weft keeps the first, logs a warning naming both declaration sites, and doesn't render the loser at all: the slot is claimed as each fragment builds, so a companion that has already lost stops before its own `build` body runs. The primary claims its slot first, so a companion can never swap over the fragment the response is actually about. Companions differing in an [identifying param](#params) derive different ids and both ride, which is what makes a left eye and a right eye a pair rather than a clash. The case worth knowing: two declarations whose deltas differ only in a *non*-identifying value look distinct in the source and collide in the DOM. When a transferring component and its target both include the same companion, the target's declaration keeps the slot — the response is the target's.

**A companion is a courtesy, not a contract.** If a companion raises, the response still belongs to the component the request was about: its render, its status, and its headers are untouched, and the failing companion shows *its own* recovery in *its own* slot. That's what keeps an action honest — a stale card that can't re-render is a display problem, not grounds for reporting a committed change as a failure. See [when a companion fails](error-handling.md#when-a-companion-fails).

### The callable contract

Action callables receive one argument — the component's resolved `params`, the same bag its `build` reads. A callable can read the component's own `derives` and `defines`, so the lookup a component already declares doesn't get written a second time inside every action:

```ruby
param :order_id
derives(:order) { |p| Oms::Order.find(p.order_id) }

performs :advance do |params|
  Oms::AdvanceOrder.call(params.order)   # the same order the render below will show
end
```

A derivation the callable forces stays forced for the rest of the response, so that's one query serving the action, the re-render, and any companions riding along — you don't have to hand the record forward to avoid a refetch.

The return value directs what happens next:

- **`nil`** (or any ignored value): re-render with the original params. The common case — the callable did its side effect; the fresh render reflects it.
- **a `Hash`**: an overlay on the request. The returned keys override wire values for *everything* the response renders — the component, its nested children, its OOB companions — an explicit `nil` clears a value, and a rich object pre-empts matching `derives` down the tree. Use this to change state on the way through: `performs :filter do |params| { page: 1 } end`. Because *any* hash return is an overlay, watch your last expression — `Hash#delete` and `merge!` return hashes, and a callable ending on one silently applies it. End a side-effect-only callable with an explicit `nil`.
- **a `Weft::Redirect`**: navigate away instead of re-rendering. Build one with `Weft.redirect`:

```ruby
performs :create do |params|
  order = Oms::CreateOrder.call(params.to_h)
  Weft.redirect(OrderDetailPage, order_id: order.id)
end
```

`Weft.redirect` takes a `Weft::Page` subclass plus params (interpolated into the page's path pattern), or a plain URL string. The Router handles transport: htmx requests get an `HX-Redirect` header, traditional form submissions get a 302.

Like every verb block — the action callable here, and the blocks for `transfers`, `recovers`, and `brings` — the callable runs against a [sandboxed `self`](#derives--lazy-server-side-derivations): `params` and lexical constants are in reach and `Kernel` is available, but nothing component-specific is. Do your side effects through the objects you call (`Oms::AdvanceOrder.call(order)`), never through a method on the component.

If the callable raises, the error walks the component's recovery chain — see [Error handling](error-handling.md).

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

**`title`** (pages only) — declares what goes in the browser tab. A static value, or a block computed from the page's params — the block is a `(params) → value` function run in the same sandbox as every other verb block:

```ruby
class OrderDetailPage < Weft::Page
  self.page_path = "/orders/:order_id"
  param :order_id
  derives(:order) { |p| Order.find(p.order_id) }

  title { |params| "Order ##{params.order.number}" }
end
```

The nearest declaration in the class ancestry wins — declare a static `title "My App"` on your base page and each concrete page overrides it (or doesn't, and inherits the app-wide default). With no declaration anywhere, the title is `"Weft"`. This is the only title channel: there's nothing to set in `build`, and nothing renders before `super` — the declaration is available to the head assembly no matter where in the lifecycle it's needed. One nearby name to keep straight: *inside* `build`, a bare `title "x"` is [Arbre](arbre.md)'s HTML tag builder and inserts a literal `<title>` element into the body — the page-title declaration lives in the class body.

## Element kwargs

Inside `build` (and inside blocks nested under it), any element accepts Weft kwargs alongside its normal HTML attributes. Weft intercepts them at render time and expands them into htmx wiring. The vocabulary has two ranks:

- **Interaction kwargs** say what request the element makes — [`action:`](#action), [`navigate:`](#navigate), [`loads:`](#loads), or any [preset](#presets). One per element, and the *value shape* is part of the claim: a Symbol `action:` is Weft's, while a String `action:` on a form is plain HTML.
- **Modifier kwargs** adjust the wiring the interaction generates. `target:` and `swap:` override where the response lands and how it swaps — whatever the interaction, and whatever its declaration or preset would have used. [`trigger:`](#trigger), [`push_url:`](#push_url), and [`confirm:`](#confirm) do the same and *also* work standalone, on an element that makes no request of its own, because htmx lets those attributes inherit from a containing element.

### `action:`

```ruby
button "Advance", action: :advance, class: "btn btn-primary"
```

Wires the element to a declared `performs`/`transfers` action on the nearest enclosing component that declares it. Expands to the full htmx set: the request (`hx-post` etc. to the action's route), the target (the component's own element, unless the action declared `target:`), the swap, and the component's current params as the payload (`hx-vals`). A Symbol that matches no enclosing component's declarations raises — a typo can't silently produce a dead button. And it isn't just for buttons and forms: `action:` works on any element — a `div` serving as a modal underlay, a table row, a badge — with htmx's default trigger (click) applying.

Add `target:` / `swap:` alongside to override, for this element only, where the response lands and how it swaps — the declaration's values stay the defaults for every other call site:

```ruby
button "Advance", action: :advance, target: "#detail-pane", swap: :fill
```

On a `form` element, `action:` additionally emits plain HTML `action` and `method` params, so the form still submits without JavaScript — and the field values themselves become the payload:

```ruby
form(action: :create) do
  input(type: "text", name: "customer_name")
  input(type: "submit", value: "Create")
end
```

### `navigate:`

```ruby
button "Next", navigate: { page: params.page + 1 }
```

Re-fetches the enclosing component with some of its params changed — a GET to the component's own route with the overridden values, replacing the component. This is the idiom for filters, sorting, and pagination: same component, different wire state. Pass `nil` to drop a param from the URL. Pairs naturally with `push_url:` when the new state should be reflected in the address bar, and takes `target:` / `swap:` overrides like any interaction kwarg.

**`navigate:` or `performs`?** `navigate:` is pure wire-state navigation: no side effects, no route of its own, honest GET semantics. The moment an interaction *does* something — writes, calls a service — it's a `performs`. And when you find yourself repeating the same override hash at many call sites, prefer a named `performs` returning that hash even without side effects: the declaration names the pattern once instead of scattering it.

Because the re-fetch renders the component standalone, only its own declared `param`s survive the round trip — so every key you override must be one the component (or a class ancestor) declares. Anything else raises `Weft::InvalidUsage` at render time; to change an *ancestor's* state instead, target the ancestor itself ([`enclosing`](arbre.md#reaching-enclosing-components) + `loads:`).

### `loads:`

```ruby
button "Show manifest", loads: Logistics::ShipmentManifest,
                        with: { shipment_id: shipment.id },
                        swap: :fill, target: "#detail-pane"
```

Loads a *different* component into a chosen DOM location on click (or whatever `trigger:` you add). `swap:` and `target:` are required — `loads:` is the fully-explicit primitive underneath the [presets](#presets), which exist to fill those in for common patterns. `with:` supplies the target component's wire params; omitted, it defaults to the enclosing component's current params. That default cuts both ways: the encloser's params are *baked into the generated URL at render time*, so when they overlap the target's own schema (or a value the browser appends, like a select's), the stale baked value competes with the fresh one. When the target should fetch clean, say so explicitly with `with: {}`.

The target must be [routable](routing.md#what-routes--and-what-doesnt) — the click fetches it at its own URL. A non-routable target (here or as a preset's Class value) raises `Weft::InvalidUsage` at render time rather than wiring a fetch that could only 404; a purely presentational target opts in with `routable!`.

### The kwarg rules

A kwarg that is unmistakably Weft's but can't make sense **raises `Weft::InvalidUsage`** at render time rather than leaking into your HTML — a mistyped action name, a `navigate:` key the component doesn't declare, a `with:` with nothing to feed. A **`nil` value always means "not this time"** (`tooltip: maybe_class`) and renders nothing. Everything else — `class:`, `data:`, raw `hx-*` strings, a real HTML `target:` on a link — passes through to the element untouched.

| Kwarg | Rank | Weft's when… | Otherwise |
| --- | --- | --- | --- |
| `action:` | interaction | the value is a Symbol naming a declared action | String values are plain HTML (`form action: "/path"`); an unmatched Symbol raises |
| `navigate:` | interaction | the value is a Hash of param overrides | any other value raises; so does re-fetching a non-routable component |
| `loads:` | interaction | the value is a component Class | any other value raises; so does a non-routable target |
| preset names (`tooltip:`, …) | interaction | the value is a Class or URL String | any other value raises; so does a non-routable Class target |
| `target:` | modifier | an interaction kwarg is present | plain HTML (`target: "_blank"` on a link works as ever) |
| `swap:` | modifier | an interaction kwarg is present | passes through as an attribute, with a one-time warning |
| `trigger:` | modifier | always | — |
| `push_url:` | modifier | always | — |
| `confirm:` | modifier | always | — |
| `with:` | feeds `loads:`/presets | `loads:` or a preset is alongside | raises |

### `trigger:`

```ruby
div(loads: Preview, with: { id: id }, swap: :fill, target: :self,
    trigger: :visible)
```

Sets when the element's request fires. Accepts the semantic symbols in the [trigger table](#trigger-values) or any raw [htmx trigger string](https://htmx.org/params/hx-trigger/) for full control (`"mouseenter once from:closest .card"`). Works standalone or alongside `action:` / `navigate:` / `loads:` / a preset. One thing to expect when inspecting output: a raw string's special characters render HTML-escaped (`keyup[altKey&&key=='A']` emits as `hx-trigger="keyup[altKey&amp;&amp;key=='A']"`) — that's correct HTML, and htmx reads it as written.

### Trigger values

| Semantic | htmx equivalent | Fires… |
| --- | --- | --- |
| `:click` | `click` | on click |
| `:click_once` | `click once` | on the first click, then never again |
| `:change` | `change` | when the value changes (selects, checkboxes) |
| `:hover` | `mouseenter once` | on first hover |
| `:visible` | `revealed` | when scrolled into view |
| `:input` | `input changed delay:300ms` | as the user types, debounced |

### `push_url:`

```ruby
button label, action: :filter, push_url: "/orders?status=#{status}"
```

Pushes a URL into the browser's address bar when the request completes, keeping the location shareable and the back button meaningful. Pass the URL string, or `true` to push the request's own URL.

### `confirm:`

```ruby
button "Delete", action: :destroy, confirm: "Delete this order?"
```

Shows the browser's native confirmation dialog before the request fires; Cancel means no request at all. Works alongside any interaction kwarg — actions, navigations, loads, presets — or standalone on a container, where htmx inheritance applies it to every request fired from inside:

```ruby
div confirm: "This affects the live feed. Continue?" do
  button "Pause", action: :pause
  button "Reset", action: :reset
end
```

There is deliberately no `prompt:` counterpart yet — htmx delivers the typed reply in a request header that action callables can't read today; the kwarg arrives once they can.

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

### Targets

Wherever a `target:` is accepted: `:self` targets the element itself, a string is a CSS selector passed through to htmx (including forms like `"closest tr"`), and an Arbre element reference targets that element by its id. In verb declarations (`performs`/`transfers`), only the selector-string form applies — `:self` and element references describe elements, which don't exist yet at class-declaration time.

## Presets

Presets bundle the `loads:` machinery into named interaction patterns — one kwarg that says what the interaction *is*, with the trigger and swap details baked in:

```ruby
button "▸", inline_expand: Oms::OrderInlineDetail,
            with: { order_id: order.id },
            target: "closest tr"
```

The kwarg's value is the component class to load (`with:` supplies its params, same as `loads:`). The gem ships these presets:

| Preset | Trigger | Swap | Target | Example |
| --- | --- | --- | --- | --- |
| `tooltip:` | `:hover` | `:fill` | supply `target:` | [Tooltip](examples/tooltip.md) |
| `inline_expand:` | `:click_once` | `:after` | supply `target:` | [Inline Expansion](examples/inline-expansion.md) |
| `lazy:` | `:visible` | `:fill` | `:self` | [Lazy Loading](examples/lazy-loading.md) |
| `modal:` | `:click` | `:fill` | supply `target:` | [Modal Dialog](examples/modal-dialog.md) |
| `load_more:` | `:click` | `:replace` | `:self` | [Click to Load](examples/click-to-load.md) |
| `infinite_scroll:` | `:visible` | `:after` | supply `target:` | [Infinite Scroll](examples/infinite-scroll.md) |
| `live_search:` | `:input` | `:fill` | supply `target:` | [Active Search](examples/active-search.md) |
| `tabs:` | `:click` | `:fill` | supply `target:` | [Tabs](examples/tabs.md) |
| `retry:` | `:click` | `:replace` | `closest .weft-error` | — |
| `reopen_stream:` | `:click` | `:replace` | `closest [sse-swap]` | — |

Where the table says "supply `target:`", the preset has no universally-right answer for where the content lands, so the call site provides it (omitting it raises immediately, with a message saying so). Explicit `swap:` and `target:` kwargs always override the preset.

`retry:` and `reopen_stream:` are the odd ones out: their value is a **URL string** rather than a component class — the failing component's own GET URL, as injected into error components via the `:retry_url` recovery param (see [Error handling](error-handling.md)). `retry:`'s baked-in target replaces the enclosing `.weft-error` box with the freshly-rendered component; `reopen_stream:` targets a closed SSE stream's wrapper so the fresh render reconnects it:

```ruby
button "Retry", retry: params.retry_url
```

### Registering your own

```ruby
Weft.register_preset :paginate, trigger: :click, swap: :replace
```

A registration names the preset and provides any of `trigger:`, `swap:`, and `target:`. From then on, `paginate:` works as an element kwarg everywhere — same machinery, your vocabulary. Naming interactions after their intent keeps call sites readable: `button "Next", paginate: OrdersPanel, with: { page: 2 }` says more than the four htmx params it expands to.

Names are checked at registration. One that collides with Weft's own element-kwarg vocabulary (`action`, `navigate`, `loads`, `trigger`, `push_url`, `swap`, `target`, `with`, `confirm` — and `prompt`, reserved) raises `Weft::InvalidDefinition`: a preset by that name would shadow the grammar itself. One that shadows a standard HTML attribute (`title`, `href`, …) registers but logs a warning — elements passing a Class or String value for that kwarg will expand as your preset instead of rendering the attribute.
