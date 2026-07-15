# Tooltip

Hovering over an element fetches a small piece of server-rendered detail — a profile card, a definition, a status readout — and places it in a bubble beside the trigger. The detail is rendered fresh from the server on first hover, then stays put.

There's no counterpart for this in the htmx examples catalog; `tooltip:` is Weft-native sugar over the same [`loads:`](../dsl.md#loads) machinery as the other shorthands. It earns its keep when the tooltip content is worth a server round-trip — live data, per-record queries — rather than static text a `title=` attribute could carry.

## The components

```ruby
TEAM = {
  "priya" => { role: "Backend",  timezone: "UTC+5:30", focus: "payments migration" },
  "marco" => { role: "Design",   timezone: "UTC+1",    focus: "checkout redesign" },
  "june"  => { role: "Support",  timezone: "UTC−8",    focus: "triage rotation" }
}.freeze

class MemberPeek < Weft::Component
  builder_method :member_peek

  param :handle

  def build(attributes = {})
    super
    member = TEAM.fetch(params.handle)
    strong params.handle.capitalize
    para "#{member[:role]} — #{member[:timezone]}"
    para "Focus: #{member[:focus]}"
  end
end

class TeamRoster < Weft::Component
  builder_method :team_roster

  def build(attributes = {})
    super
    h3 "On the project"
    ul do
      TEAM.each_key do |handle|
        li style: "position: relative" do
          span handle.capitalize, class: "peek-trigger",
               tooltip: MemberPeek, with: { handle: handle }, target: "#peek-#{handle}"
          div id: "peek-#{handle}", class: "peek-bubble",
              style: "position: absolute; left: 8rem; top: 0;"
        end
      end
    end
  end
end
```

(The `TEAM` hash stands in for your data layer; the inline styles are the minimum to float each bubble beside its row — real styling belongs in your stylesheet.)

## How it works

**Hover fetches; the bubble receives.** [`tooltip:`](../dsl.md#shorthands) presets trigger `:hover` and swap `:fill`; the call site says where the content lands. Each name targets its own empty bubble div (`target: "#peek-#{handle}"`), so every row has an independent tooltip slot. The bubbles start empty and cost nothing until hovered.

**`:hover` means *first* hover.** The semantic trigger expands to htmx's `mouseenter once` — the fetch happens the first time the pointer enters, and never again. Be clear about what that buys and what it doesn't: Weft delivers the *content*, once, lazily. It does not show and hide the bubble as the pointer comes and goes — that's presentation, and it belongs to CSS (a `.peek-bubble` hidden until `li:hover`, for instance). After the first hover, showing the tooltip again is free, because the content is already in the page.

**Per-row wire params, one component.** Every trigger loads the same `MemberPeek` class with a different `with: { handle: ... }` — the component is written once and addressed per record, which is the same shape as every list-plus-detail pattern in this catalog.

## On the wire

The initial render — each name wired, each bubble empty:

```html
<li style="position: relative">
  <span class="peek-trigger" hx-get="/_components/member_peek?handle=priya"
        hx-swap="innerHTML" hx-target="#peek-priya"
        hx-trigger="mouseenter once">Priya</span>
  <div id="peek-priya" class="peek-bubble"
       style="position: absolute; left: 8rem; top: 0;"></div>
</li>
```

The first hover over Priya issues `GET /_components/member_peek?handle=priya`, and the bubble fills:

```html
<div id="member-peek-priya">
  <strong>Priya</strong>
  <p>Backend — UTC+5:30</p>
  <p>Focus: payments migration</p>
</div>
```

## Related

- [Inline Expansion](inline-expansion.md) — the other Weft-native shorthand: click-driven detail that lands *after* its trigger instead of in a bubble.
- [Lazy Loading](lazy-loading.md) — the same load-once deferral, triggered by visibility instead of the pointer.
- The [shorthands table](../dsl.md#shorthands) in the DSL reference.
