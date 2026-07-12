# Tabs

A row of tab buttons over a content panel. Clicking a tab fetches that tab's content from the server and swaps it into the panel — each tab is a component, and the server is the single source of truth for what's in it.

This is Weft's take on [htmx's server-driven tabs example](https://htmx.org/examples/tabs-hateoas/). htmx's catalog also carries a second, JavaScript-flavored tabs variant for keeping tab state purely client-side; in Weft that fork in the road doesn't arise — components are server-rendered by design, so *this* pattern is the answer to both.

## The components

```ruby
class DescriptionTab < Weft::Component
  builder_method :description_tab
  routable!

  def build(attributes = {})
    super
    para "The Fairweather field kit packs a tarp, a stove, and a first-aid pouch " \
         "into a single roll-top bag. Everything clips to the outside webbing."
  end
end

class ShippingTab < Weft::Component
  builder_method :shipping_tab
  routable!

  def build(attributes = {})
    super
    para "Orders placed before noon ship the same day. Standard delivery takes " \
         "three to five business days; expedited arrives in two."
  end
end

class ReturnsTab < Weft::Component
  builder_method :returns_tab
  routable!

  def build(attributes = {})
    super
    para "Unused kits can be returned within thirty days for a full refund. " \
         "Field-tested kits can be exchanged for store credit."
  end
end

class ProductTabs < Weft::Component
  builder_method :product_tabs

  def build(attributes = {})
    super
    nav do
      button "Description", tabs: DescriptionTab, target: "#product-tab-panel"
      button "Shipping",    tabs: ShippingTab,    target: "#product-tab-panel"
      button "Returns",     tabs: ReturnsTab,     target: "#product-tab-panel"
    end
    div id: "product-tab-panel" do
      description_tab
    end
  end
end
```

## How it works

**Every button aims at the same panel.** [`tabs:`](../dsl.md#shorthands) presets trigger `:click` and swap `:fill`; the call site supplies the shared target. Clicking a tab fetches its component and replaces the panel's contents. The default tab is simply pre-rendered into the panel — the initial state is the same component a click would fetch.

**`routable!` makes contentful-but-stateless tabs fetchable.** A component normally earns its route by declaring attributes or verbs ([Routing](../routing.md)); these tabs declare neither, so without help they would render fine *and* be unreachable over the wire — the buttons would point at URLs that 404. `routable!` opts them in explicitly. (Tabs that take wire state — an `order_id`, say — get their routes the ordinary way and don't need it.)

**The selected tab isn't highlighted — yet.** Only the panel is swapped; the buttons themselves never re-render, so nothing moves a "selected" class around. htmx's example re-renders the whole tab bar with each click for exactly this reason. The Weft equivalent of that move is to give the wrapping component the state and re-render it whole — `attribute :tab` plus [`navigate: { tab: "shipping" }`](../dsl.md#navigate) on each button replaces the entire `ProductTabs` component, selected styling included, at the cost of re-sending the bar with every switch. Start with the version above; reach for `navigate:` when the highlight matters.

## On the wire

The initial render — three wired buttons, and the panel holding the default tab:

```html
<div id="product-tabs">
  <nav>
    <button hx-get="/_components/description_tab" hx-swap="innerHTML"
            hx-target="#product-tab-panel" hx-trigger="click">Description</button>
    <button hx-get="/_components/shipping_tab" hx-swap="innerHTML"
            hx-target="#product-tab-panel" hx-trigger="click">Shipping</button>
    <button hx-get="/_components/returns_tab" hx-swap="innerHTML"
            hx-target="#product-tab-panel" hx-trigger="click">Returns</button>
  </nav>
  <div id="product-tab-panel">
    <div id="description-tab">
      <p>The Fairweather field kit packs a tarp, a stove, and a first-aid pouch into a single roll-top bag. Everything clips to the outside webbing.</p>
    </div>
  </div>
</div>
```

Clicking Shipping issues `GET /_components/shipping_tab`, and the response fills the panel:

```html
<div id="shipping-tab">
  <p>Orders placed before noon ship the same day. Standard delivery takes three to five business days; expedited arrives in two.</p>
</div>
```

## Related

- [Active Search](active-search.md) — the same fill-a-stable-container shape, driven by typing instead of clicks.
- [`abstract!` and `routable!`](../routing.md#abstract-and-routable) in the routing reference.
- The [shorthands table](../dsl.md#shorthands) in the DSL reference.
