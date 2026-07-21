# Click to Load

A list that shows its first page up front, with a "load more" button at the bottom. Clicking the button replaces it with the next page of results — which brings its own button, until the data runs out. The page never reloads, and nothing already on screen is disturbed.

This is Weft's take on [htmx's click-to-load example](https://htmx.org/examples/click-to-load/), with the same cast of agents. One structural difference is worth knowing up front: htmx's version returns a loose fragment of sibling `<tr>`s to splice into a table, but a Weft component always renders exactly one wrapper element. So the Weft shape is a *chunk* — one element holding a page of results plus the next button — and each chunk lands where the previous button was. (For tables specifically, see [Infinite Scroll](infinite-scroll.md), whose append-style swap plays naturally with `<tbody>` chunks.)

## The components

```ruby
AGENTS = (1..24).map { |n| { name: "Agent Smith", email: "void#{n}@null.org", number: n } }.freeze

class AgentRows < Weft::Component
  builder_method :agent_rows

  PER_PAGE = 6

  param :page, default: 1

  def build(attributes = {})
    super
    batch = AGENTS[(params.page - 1) * PER_PAGE, PER_PAGE]
    batch.each do |agent|
      div { strong agent[:name]; text_node " — #{agent[:email]} (##{agent[:number]})" }
    end
    if params.page * PER_PAGE < AGENTS.size
      button "Load More Agents...", load_more: AgentRows, with: { page: params.page + 1 }
    end
  end
end
```

(The `AGENTS` array stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

Render a bare `agent_rows` wherever the list lives — its `page` param defaults to 1 — and the pattern takes care of itself from there.

## How it works

**One preset, no ceremony.** [`load_more:`](../dsl.md#presets) is a preset over the [`loads:`](../dsl.md#loads) machinery: trigger `:click`, swap `:replace`, target `:self`. In plain terms — when this button is clicked, fetch the named component and put it where the button was. The call site supplies only what varies: which component to load (`AgentRows`, the component's own class) and its wire params (`with: { page: params.page + 1 }`).

**The component is a chunk, not the whole list.** Each `AgentRows` instance renders one page of agents and, when more remain, the button that fetches the next chunk *in its own place*. Clicking never touches the agents already on screen; the button alone is replaced, and the new chunk arrives with its own button. The recursion bottoms out naturally — the `if` guard means the final chunk simply renders no button.

**Params make the chunk addressable.** Declaring `param :page, default: 1` gives the component a route ([Routing](../routing.md)) and coerces the wire value: `page=2` arrives as the string `"2"` and reaches `params.page` as the Integer `2`, because the default is an Integer.

**A component can load itself.** `load_more: AgentRows` inside `AgentRows`'s own `build` is unremarkable — the class reference is evaluated at render time, so self-reference needs no tricks.

## On the wire

The initial render (or `GET /_components/agent_rows?page=1`):

```html
<div id="agent-rows-1">
  <div><strong>Agent Smith</strong> — void1@null.org (#1)</div>
  <!-- … five more agents … -->
  <button hx-get="/_components/agent_rows?page=2" hx-swap="outerHTML"
          hx-target="this" hx-trigger="click">Load More Agents...</button>
</div>
```

Every htmx attribute there came from the one `load_more:` kwarg. Clicking issues `GET /_components/agent_rows?page=2`, and the response replaces the button:

```html
<div id="agent-rows-2">
  <div><strong>Agent Smith</strong> — void7@null.org (#7)</div>
  <!-- … -->
  <button hx-get="/_components/agent_rows?page=3" hx-swap="outerHTML"
          hx-target="this" hx-trigger="click">Load More Agents...</button>
</div>
```

The last page (`GET /_components/agent_rows?page=4`) renders its agents and no button — the interaction retires itself.

## Related

- [Infinite Scroll](infinite-scroll.md) — the same next-page mechanic, triggered by scrolling instead of a click, in a real table.
- [Lazy Loading](lazy-loading.md) — deferring one expensive section rather than paginating many.
- The [presets table](../dsl.md#presets) in the DSL reference, including how to register your own preset.
- For pagination that *replaces* the current page instead of accumulating, [`navigate:`](../dsl.md#navigate) is the better verb.
