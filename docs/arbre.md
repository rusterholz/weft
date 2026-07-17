# Arbre: the HTML layer

Weft builds HTML with [Arbre](https://github.com/activeadmin/arbre), the object-oriented HTML builder from the ActiveAdmin family. This isn't an implementation detail you can ignore: **every `Weft::Component` and `Weft::Page` *is* an Arbre component.** The `build` method you write, the `builder_method` you declare, the `h1`/`div`/`para` calls inside — all Arbre. When Weft feels like "describing the UI in Ruby," Arbre is the part doing the describing.

Arbre's own upstream documentation is famously thin, so this document doesn't assume you'll fill gaps elsewhere. It's the working knowledge a Weft author needs — Arbre's model, its conventions, and its genuinely surprising corners — shown the way you'll use it in Weft. Everything here is verified against the Arbre versions Weft supports (1.7 through 2.x; the handful of behavioral differences are [at the end](#arbre-1x-vs-2x)).

**In this document:**

- [The element tree](#the-element-tree)
- [Building HTML](#building-html): [elements and arguments](#elements-and-arguments), [attributes](#attributes), [text](#text)
- [Blocks and method lookup](#blocks-and-method-lookup)
- [Inside `build`: the component contract](#inside-build-the-component-contract)
- [Receiving caller content](#receiving-caller-content)
- [Working with the tree](#working-with-the-tree)
- [Forms](#forms)
- [Testing components](#testing-components)
- [Arbre 1.x vs 2.x](#arbre-1x-vs-2x)

## The element tree

Arbre doesn't concatenate strings — it builds a tree of Ruby objects that mirrors your HTML, and renders it with `to_s` at the end. Every `div` or `span` you create is an object (`Arbre::HTML::Div`, `Arbre::HTML::Span`…) with a parent, children, attributes, and methods. Until rendering, the tree is live: you can hold references to elements, add to them out of order, inspect them, move them.

The mechanism that makes nested blocks work is the **current element**. There's always exactly one element currently receiving new children. When you call `div do ... end`, Arbre:

1. creates the `Div`,
2. adds it as a child of the current element,
3. makes the new div the current element,
4. runs your block (so everything created inside lands in the div),
5. restores the previous current element.

That's the whole trick. Every pattern in this document — containers, `within`, method lookup — is a variation on "who is the current element right now, and where do new children go?"

## Building HTML

### Elements and arguments

Every HTML5 element is available as a builder method: `div`, `span`, `table`, `nav`, `section`, `input`, `select` — all of them. Each accepts the same argument convention:

| Form | Example | Meaning |
| --- | --- | --- |
| bare | `hr` | empty element |
| string first | `h1 "Trivia Night"` | first non-hash argument becomes the content |
| hash last | `div class: "event-card"` | trailing hash becomes the attributes |
| both | `h1 "Trivia Night", class: "title"` | content and attributes |
| block | `div(class: "event-card") { h1 "..." }` | block builds the children |

Self-closing tags (`br`, `hr`, `img`, `input`, `meta`, `link`, and friends) close themselves — `img src: "map.png"` renders `<img src="map.png"/>`.

> **The one exception: paragraphs are `para`, not `p`.** Ruby's built-in `Kernel#p` (the debug printer) can't be shadowed safely, so Arbre names the `<p>` builder `para`. If you write `p "some text"`, nothing errors — the text goes to your server's stdout and no paragraph renders. This costs every newcomer an hour once; the [tutorial](tutorial.md#3-your-first-page) tries to make sure it isn't you.

### Attributes

Set attributes at creation time (the trailing hash), or programmatically on the element:

```ruby
div class: "event-card", id: "bbq"

div do |card|
  card.set_attribute "aria-live", "polite"
  card.add_class "highlighted"
  card.remove_class "pending"
  card.id = "custom-id"
end
```

`get_attribute`, `has_attribute?`, and `remove_attribute` round out the set, and `class_list` returns the classes as an inspectable collection.

Hashes under `data:` flatten into hyphenated data attributes, nesting included:

```ruby
div data: { controller: "chart", series: { color: "teal" } }
# => <div data-controller="chart" data-series-color="teal"></div>
```

Attributes with `nil` values are omitted from the output. (Empty-*string* values differ by Arbre version — [see below](#arbre-1x-vs-2x).)

### Text

Four ways to put text in the tree:

```ruby
span "Priya"                       # 1. as the content argument — the usual way
span { "Priya" }                   # 2. as the block's return value
text_node "3 attending"            # 3. explicitly, wherever you are
text_node "<em>live</em>".html_safe # 4. raw HTML — bypasses escaping, trusted content only
```

Way 2 comes with the sharpest edge in Arbre. A block's return value becomes text **only if the element has no children yet**; the moment anything else was added, the return value is silently discarded:

```ruby
li { "Priya" }              # <li>Priya</li> — works
li do
  strong "Priya"
  " — yes"                  # silently discarded!
end                         # <li><strong>Priya</strong></li>
```

No error, no warning — the text just isn't there. Whenever a block mixes elements and loose text, use `text_node` for the text:

```ruby
li do
  strong "Priya"
  text_node " — yes"        # <li><strong>Priya</strong> — yes</li>
end
```

## Blocks and method lookup

When you call a method inside an Arbre block, what actually receives it? Two rules cover nearly everything:

**Rule 1 — the routing chain.** A method the enclosing object doesn't itself define is routed by Arbre, in order: methods on the **current element** first (that's how `add_class` or `set_attribute` work bare inside a block), then keys in the context's **assigns** hash, then the **helpers** object, and finally a normal `NoMethodError`. Inside a Weft component you rarely think about assigns and helpers — your component's own methods and ordinary Ruby scope do the work — but the chain matters when you use `Arbre::Context` directly ([Testing](#testing-components)) and when names collide (below).

**Rule 2 — real methods win.** The routing only happens via `method_missing`, so a method that *does* exist on the enclosing object binds there, not to the element you're inside. Your component's own helper methods work naturally inside nested blocks for exactly this reason (during `build`, the enclosing object is your component). But the same rule has a trap: generic element methods like `add_child`, `content`, and `parent` exist on *every* Arbre object — including your component and the root context — so calling them bare inside a `div` block does not touch the div. When you mean the element, take it as a block parameter and be explicit:

```ruby
div do |d|
  d.add_child something    # unambiguously the div
end
```

(Tag-specific methods — `add_class`, `set_attribute`, `id=` — aren't defined on components or contexts, so they route to the current element reliably. It's the tree-plumbing methods that need the explicit receiver.)

**Name collisions** follow from rule 1's element check: every HTML tag name is a method on the current element. A local, an assign, or a model reference named `address`, `time`, `data`, `table`, or any other tag name loses to the tag builder:

```ruby
address = venue_address(event)
div do
  address        # builds an empty <address> element — not your variable!
end
```

Rename the variable (`venue`), or hold data in something the chain checks earlier. This one is worth remembering any time an inexplicably empty element shows up in your output.

## Inside `build`: the component contract

A component describes its structure in `build`. The Weft-idiomatic shape takes a single attributes hash and calls `super` before building:

```ruby
class EventSummary < Weft::Component
  builder_method :event_summary

  param :event_id

  def build(attributes = {})
    super
    event = EventStore.find(params.event_id)
    h3 event.name
    para "#{event.date} — #{event.location}"
  end
end
```

**Arguments arrive positionally — always.** When a call site writes `event_summary(event_id: "bbq", class: "compact")`, Arbre collects the arguments and passes them positionally to `build`; the keywords become one trailing hash. Declaring Ruby keyword parameters (`def build(event_id:)`) raises `ArgumentError: wrong number of arguments`. Take the hash.

**`super` is where the hash becomes reality.** In a Weft component, `super` extracts your declared params into `params`, applies whatever remains as HTML attributes on the wrapper element (that's where `class: "compact"` went), and sets the wrapper's DOM id ([derived from your first param](dsl.md#params)). Skip `super` and none of that happens — the classic symptom is a component that ignores the `class:` you pass it.

**Rich objects ride the same hash — pull them out first.** Wire params (declared with `param`) are for values that travel in URLs. When a call site already holds a rich object, passing it in the hash is fine — just `delete` it before `super` so it doesn't get sprayed onto the wrapper as an HTML attribute:

```ruby
class AttendeeRow < Weft::Component
  builder_method :attendee_row

  def build(attributes = {})
    @attendee = attributes.delete(:attendee)   # rich object out first
    super
    td @attendee.name
    td @attendee.answer
  end

  def tag_name
    "tr"
  end
end
```

**`tag_name` picks the wrapper element.** Components render as `<div>` by default; override `tag_name` to be a `tr`, `span`, `li`, `section` — whatever the surrounding HTML demands, as above.

**`builder_method` resolves by name, at call time.** The macro generates a method that looks the class up as a constant (`insert_tag ::AttendeeRow`) each time it's called. Two consequences: it plays well with code reloading (the freshest definition wins), and it requires the class to be a real, resolvable constant — which is mostly invisible in an app but occasionally bites in tests ([below](#testing-components)).

## Receiving caller content

Composable components take a block of caller content:

```ruby
event_card(event_id: event.id) do
  para "Bring a dish to share!"
end
```

One fact makes this work, and it's worth internalizing: **the caller's block runs *after* `build` returns.** First your `build` lays out the component's structure; then the caller's children arrive, one `add_child` at a time. Anything your `build` set up — including instance variables — is in place by the time they do.

By default those children land on the wrapper element, after your structure. When they should land *inside* a specific element instead — the card's body, not next to its header — declare the container with Weft's macro:

```ruby
class EventCard < Weft::Component
  builder_method :event_card
  adds_children_to :@body

  param :event_id

  def build(attributes = {})
    super
    h3 EventStore.find(params.event_id).name   # structure — lands on the wrapper
    @body = div(class: "event-card-body")     # caller content lands in here
  end
end
```

The macro generates the underlying Arbre pattern: an `add_child` override that redirects to `@body` once it exists (during `build` it doesn't yet, so your own structural elements pass through normally). The `:@ivar` spelling is a deliberate reminder that *you* must assign that ivar in `build` — Weft raises a pointed error if you forget. Details in [the DSL reference](dsl.md#other-class-body-declarations).

Hand-roll the override only when one redirect target isn't enough — a multi-slot component with `header`/`body`/`footer` sections, say, where each section method fills a different internal element and `add_child` picks a default. The generated pattern above is the template to follow.

## Working with the tree

Because elements are objects, you can build out of order. Hold a reference, come back later with `within`:

```ruby
def build(attributes = {})
  super
  @summary = div(class: "summary")
  @details = div(class: "details")

  within @details do
    para "Doors at 6:30"       # lands in @details
  end
  within @summary do
    para "21 attending"        # lands in @summary — after @details was filled
  end
end
```

`within(element) { ... }` temporarily makes any element the current one. It's the tool for components whose sections fill up at different times.

For inspection, the tree is searchable: `find_by_tag("a")` and `find_by_class("nav-item")` return matching descendants, `parent` and `ancestors` walk upward, and `children` enumerates directly. These shine in tests ([below](#testing-components)) and in the rare component that post-processes its own output.

Two content accessors to keep straight: `content` *reads* the children rendered as HTML — but `content=` **replaces**, clearing every existing child first:

```ruby
div do |d|
  span "gone"
  d.content = "replacement"    # the span is destroyed
end                            # <div>replacement</div>
```

It's the right tool for wholesale swaps and a footgun everywhere else. To add without destroying, create elements normally or use `text_node`.

## Forms

Forms are ordinary Arbre: `form`, `label`, `input`, `select`, `option`, `textarea` are tag builders like any other, and you compose them like any other markup. What Weft adds is the wiring — `form(action: :submit)` connects the form to a declared action, with htmx submission and a no-JavaScript fallback emitted for free ([the DSL reference](dsl.md#action) has the mechanics; the [tutorial](tutorial.md#7-taking-rsvps) builds a full working form).

Two field-level idioms worth knowing:

- **Field names pair with declared params.** In a Weft form, an `input name: "answer"` reaches the action callable as `params.answer` when the component declares `param :answer` — and component params that *aren't* form fields need a hidden input to travel. The [tutorial](tutorial.md#7-taking-rsvps) walks through both halves.
- **Array parameters use the `name[]` convention:** `input type: "checkbox", name: "toppings[]", value: "olives"` — submitted values arrive as an array.

## Testing components

Weft components render to a string with one call — no server, no request:

```ruby
RSpec.describe AttendeeList do
  it "lists each attendee with their answer" do
    html = AttendeeList.render(event_id: "trivia-night")
    expect(html).to include("Priya — yes")
    expect(html).to include('id="attendee-list-trivia-night"')
  end
end
```

`Component.render(**attrs)` is the gem-provided entry point and covers most component testing. When you want the element tree rather than the string — asserting on classes, structure, or specific descendants — build a context and search it:

```ruby
ctx = Arbre::Context.new do
  attendee_list(event_id: "trivia-night")
end
list = ctx.children.first
expect(list.class_list).to include("roster")
expect(ctx.find_by_tag("li").length).to eq(2)
```

Three Arbre-specific notes for test code:

- **Give test component classes real names.** `builder_method` resolves its class by name at call time, so an anonymous class (`Class.new(Weft::Component)`) with a stubbed `name` raises `NameError` the first time its builder is invoked — and under Arbre 1.x, even `insert_tag` with a truly anonymous class crashes. Define named classes (a `TestCard = Class.new(...)` constant works) rather than fighting it.
- **Pass data via assigns, not local-variable capture,** when a context block needs outside data: `Arbre::Context.new(event: event) { ... }` makes `event` resolve through Arbre's lookup chain — the same resolution production code uses — where a captured local would quietly bypass it.
- **The helpers slot** (`Arbre::Context.new(assigns, helpers)`) makes any object's methods callable inside the block. Weft renders components without helpers, so tests should too, unless you're testing raw Arbre code that expects them.

## Arbre 1.x vs 2.x

Weft supports Arbre 1.7 through 2.x — relevant if your app also carries ActiveAdmin, which historically pins Arbre 1.x. The behavioral differences, verified against both:

| Behavior | Arbre 1.x | Arbre 2.x |
| --- | --- | --- |
| Component CSS class | auto-adds the snake-cased class name (`class="fancy_box"`) | nothing added automatically |
| `<table>` attributes | auto-adds `border="0" cellspacing="0" cellpadding="0"` | nothing added |
| Empty-string attribute values | omitted from output | rendered (`foo=""`) |
| Anonymous component classes | `insert_tag` crashes (`undefined method 'demodulize' for nil`) | works |

Writing code that behaves identically on both comes down to two habits: **add your CSS classes explicitly** (never lean on 1.x's auto-class — under 2.x your styling silently disappears), and **name your component classes** (see [Testing](#testing-components)). If you're styling tables, remember 1.x injects those legacy attributes into your output.
