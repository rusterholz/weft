# How params flow

A Weft component's data — the values it renders from, the record it looks up, the id it needs to refresh itself — all arrive through one object: `params`. This page follows that data from the moment a request lands to the moment a component re-renders itself, and shows where each of the four declarations (`param`, `receives`, `derives`, `defines`) fits. For the precise behavior of each, see [the DSL reference](dsl.md#params); this page is the map, not the legend.

The whole model in one breath: **a request's params flow in and down the render tree; each component pulls out the ones it declares; and each component renders carrying enough of its own wire state that a later request — a refresh, an action — can reconstruct it from scratch.**

## A request comes in

Every render starts with a request, and a request carries **wire params**: the query string, the path segments, and any form body, all as strings. Weft routes the request to a page (or a standalone component), which resolves its declared `param`s from those wire values — coercing each into its declared `type:`, and filling in defaults where the request said nothing.

```ruby
class OrderPage < Weft::Page
  self.page_path = "/orders/:order_id"
  param :order_id
end
```

A GET to `/orders/42` gives this page `params.order_id == "42"`. Nothing else about the request — session, headers, cookies — is part of `params`; that channel is deliberately just the request's own parameters. (For per-request identity like the current user, see [Application patterns](app-patterns.md#authentication-and-sessions).)

## Params flow down the render tree

A page is rarely one component. It embeds others, which embed others. Within a single render, **each component starts from a copy of its nearest ancestor's resolved params** — it sees everything above it in the tree, nothing beside it.

```ruby
class OrderPage < Weft::Page
  param :order_id

  def build(attributes = {})
    super
    order_summary            # embedded — no arguments
  end
end

class OrderSummary < Weft::Component
  builder_method :order_summary
  # declares no order_id of its own …

  def build(attributes = {})
    super
    h2 "Order #{params.order_id}"   # … yet reads it, inherited from the page
  end
end
```

`OrderSummary` never declares `order_id`, but because it renders inside a page that has it, it reads `params.order_id` for free. This is why embedding is so quiet in Weft: a child that needs what its parent already holds just reads it. Declaring the key anyway (`param :order_id`) is often worth it — it documents the dependency and, as the next sections show, lets the child stand on its own — but it isn't required merely to *read* an inherited value.

## Four doors: how a component gets what it needs

When a component wants to control a value rather than inherit it, it declares that value — through whichever of the four doors suits the value's nature:

- **`param`** — wire state, small enough to travel in a URL: an id, a page number, a filter. Comes from the request, or is inherited from above.
- **`derives`** — a value the component computes for itself, lazily, the first time it's read.
- **`defines`** — a static value a subclass pins; sugar over `derives`.
- **`receives`** — a rich object a caller hands over directly: a record, a built collection, anything that can't ride a query string.

A single key can have more than one door, and they resolve in a fixed order — a handed value beats a request overlay (a hash a verb block returned earlier in the request) beats a wire value beats an inherited value beats a derivation beats a default. The [DSL reference](dsl.md#how-the-doors-combine) lays out that precedence and the useful *dual* combinations; the shape to carry away here is that all four doors land in the same `params`, read the same way (`params.name`).

Three of the four are open to every verb block too — an action callable, a `transfers`, `brings` or `recovers` block all read the same `param`, `derives` and `defines` a `build` would. Only `receives` is missing there, and it has to be: a hand-off comes from a call site, and a request arriving over the wire has none. When a block needs such a key, give it a second door.

## What a component keeps for itself

Here is the pivot that makes the whole system hold together: **only a component's own declared `param`s are serialized.** When Weft renders a component, it bakes that component's wire params into the things that will make the *next* request on its behalf —

- its **refresh URL** (`refreshes`) and **stream URL** (`pushes`),
- the **payload of every action** it declares (`performs`, `transfers`, `dismisses`).

The other three doors never serialize: you can't put an `Order` object in a query string, and a derived value can always be re-derived. So what travels forward is exactly the URL-safe wire state the component declared with `param`, and nothing else. Inherited values don't travel either — a child that merely *read* its parent's `order_id` doesn't carry it. A child that needs `order_id` on the next request must declare it.

The same discipline applies to a component's HTML attributes. Take a `StatCard`: a small self-refreshing tile whose class body declares `builder_method :stat_card`, so a parent builds it by that name. Chrome passed at its call site (`stat_card(class: "wide", name: "picker")`) exists only in that in-page render — a wire re-render rebuilds the component from its params alone, and the call-site attributes are gone. An attribute the component *depends on* (a `name` the pattern reads, an ARIA role) belongs inside `build` via `set_attribute`, where every render path reproduces it.

## The round trip: refresh and actions

This is the payoff. Because a rendered component carries its own wire params, it can regenerate itself without its parent in the picture:

- A **refresh** is a GET to the component's own route, its own params in the query string. Weft routes straight to that component, resolves those params from the wire — the first step again — and re-renders.
- An **action** is a POST (or DELETE) to the component's route, its params in the payload. The callable runs, then the component re-renders — and the re-render, nested components and OOB companions included, resolves against the *same request wire*, with the callable's returned hash overlaid on top. One universe per request, amended by the verbs that run in it: no matter how rendering flows inside a request (an action re-render, a `transfers` hand-off, an error recovery), a component that reads a wire param keeps reading it, without any outer component relaying it.

The callable and the render that follows it are two points on **one chain**, not two independent resolutions. Weft composes the component's params from the wire, hands that to the callable, layers whatever the callable returned on top, and passes the result on to the render — which branches it the same way a child branches its parent's. So a callable reads the same `derives` its `build` does, and a derivation it forces is already a value by the time the render, and the companions riding alongside, read the same key. One lookup, one response.

So "render with enough to get where it needs" is literal: whatever a component will need to reconstruct itself on the next request, it must hold as its own `param`s at render time, because that is what gets serialized into the refresh URL and the action payload. That `StatCard`, embedded as `stat_card(status: "hot")`, keeps refreshing correctly *only* if it declares `param :status` — otherwise the refresh request carries no status and the standalone re-render has nothing to go on.

## Lists, and why `receives` exists

Inheritance flows one value down to every descendant — which is exactly wrong for a list, where each row needs a *different* value. Siblings share their parent's bag; they can't each inherit a distinct id. So the parent must **hand** each row its own value, and that is what `receives` is for:

```ruby
class ContactRow < Weft::Component
  builder_method :contact_row

  param :contact_id       # serialized — lets the row refresh and act on its own
  receives :contact_id    # handed — the table gives each row its distinct id
end

class ContactsTable < Weft::Component
  builder_method :contacts_table

  def build(attributes = {})
    super
    tbody do
      CONTACT_BOOK.each_key { |id| contact_row(contact_id: id) }
    end
  end
end
```

The `receives :contact_id` is what consumes the `contact_row(contact_id: id)` hand-off — without it, that kwarg would fall through and render as a stray HTML attribute. The `param :contact_id` alongside it is what lets each row stand on its own: when a row fires its delete action, its id is already serialized into the payload, so the server knows which contact to remove. Handed when embedded, wire-borne when acting — two doors, one key. This *dual* is the backbone of every interactive list; you'll see it in [Delete Row](examples/delete-row.md) and [Edit Row](examples/edit-row.md).

## The shape of it

End to end: a request's wire params resolve into the top component and flow down the tree; each component reads what it inherits and declares what it wants to own; at render time each bakes its own wire params into its refresh URL and action payloads; and the next request — refresh or action — arrives carrying exactly what that component needs to do it all again. Data in from the wire, data down the tree, data forward into the next request. That loop is the whole of it.

That loop moves *data* down the tree. Once in a while a component needs to reach the other way — *up* the tree, for an ancestor's **identity** rather than its data: a nested pager needs its enclosing panel's route and DOM id to aim a swap at it. That's a separate affordance, [`closest` / `enclosing`](arbre.md#reaching-enclosing-components) — not part of the params flow, but its natural complement. Params come *to* you; identity you reach *for*.
