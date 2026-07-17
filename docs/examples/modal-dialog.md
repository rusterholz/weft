# Modal Dialog

A button opens a dialog floating over a dimmed page; pressing Close — or clicking the dimmed backdrop — makes it go away. The dialog is a component fetched on demand, and closing it is simply removing it from the DOM.

This is Weft's take on [htmx's custom modal example](https://htmx.org/examples/modal-custom/). htmx's version reaches for hyperscript to wire up the close behavior; in Weft the close is a [`dismisses`](../dsl.md#dismisses--remove-from-the-dom) action, so there's no JavaScript beyond what Weft already ships. (htmx's catalog also carries UIkit and Bootstrap modal variants — integrating with a CSS framework's modal machinery is out of scope here.)

## The components

```ruby
class TourDialog < Weft::Component
  builder_method :tour_dialog

  dismisses :close

  def build(attributes = {})
    super
    # Underlay and panel are siblings, so clicks on the panel never reach
    # the underlay. Inline styles are the minimum to dim and center —
    # real styling belongs in your stylesheet.
    div action: :close,
        style: "position: fixed; inset: 0; background: rgba(0, 0, 0, 0.4);"
    div style: "position: fixed; top: 20%; left: 50%; transform: translateX(-50%); " \
               "background: white; padding: 1.5rem 2rem; border-radius: 6px;" do
      h3 "Book a tour"
      para "Our next open house is Saturday at noon. Come see the workshop, " \
           "meet the team, and try the tools yourself."
      button "Close", action: :close
    end
  end
end

class TourPromo < Weft::Component
  builder_method :tour_promo

  def build(attributes = {})
    super
    button "Book a tour", modal: TourDialog, target: "#modal-slot"
    div id: "modal-slot"
  end
end
```

## How it works

**Opening is a load into a stable slot.** [`modal:`](../dsl.md#presets) presets trigger `:click` and swap `:fill`; the call site supplies the target. Clicking the button fetches `TourDialog` and fills the empty `#modal-slot` div with it. The slot is permanent page structure — it outlives any dialog placed in it, so the modal can be opened again after closing.

**Closing is a dismissal.** `dismisses :close` declares a DELETE action whose swap removes the component from the page entirely — and for a modal, removed from the DOM *is* closed. The dialog vanishes, the slot div stays, and the page underneath was never touched. Give the dismissal a block (`dismisses :close do |params| ... end`) if closing should also do something server-side, like recording that the tour offer was seen.

**The underlay closes too — same action, different element.** [`action:`](../dsl.md#action) isn't just for buttons: on the underlay div it expands to exactly the same wiring as the Close button, and htmx's default trigger for a div is a click. Because the underlay and the content panel are *siblings* — the underlay covers the viewport, the panel floats above it — a click on the panel never bubbles to the underlay, so only clicks on the dimmed backdrop dismiss.

**Closing is a round trip.** htmx's custom modal closes instantly, client-side; Weft's close asks the server first. That's the trade for writing no close-handling JavaScript: a request on the wire per dismissal, in exchange for one declaration and a place to hang side effects. For a modal on a reasonable connection the difference isn't perceptible, but it's worth knowing which one you're getting.

## On the wire

The initial render — a wired trigger button and an empty slot:

```html
<div id="tour-promo">
  <button hx-get="/_components/tour_dialog" hx-swap="innerHTML"
          hx-target="#modal-slot" hx-trigger="click">Book a tour</button>
  <div id="modal-slot"></div>
</div>
```

Clicking the button issues `GET /_components/tour_dialog`, and the dialog fills the slot. Underlay and Close button carry identical dismissal wiring:

```html
<div id="tour-dialog">
  <div style="position: fixed; inset: 0; background: rgba(0, 0, 0, 0.4);"
       hx-delete="/_components/tour_dialog/close" hx-target="#tour-dialog"
       hx-swap="delete" hx-vals="{}"></div>
  <div style="position: fixed; top: 20%; left: 50%; transform: translateX(-50%); background: white; padding: 1.5rem 2rem; border-radius: 6px;">
    <h3>Book a tour</h3>
    <p>Our next open house is Saturday at noon. Come see the workshop,
       meet the team, and try the tools yourself.</p>
    <button hx-delete="/_components/tour_dialog/close" hx-target="#tour-dialog"
            hx-swap="delete" hx-vals="{}">Close</button>
  </div>
</div>
```

Clicking either one issues `DELETE /_components/tour_dialog/close`. The response is a `200` whose body htmx discards — a `delete` swap removes the target element no matter what came back — leaving `#modal-slot` empty again.

## Related

- [Browser Dialogs](browser-dialogs.md) — when a native `confirm()` box is dialog enough.
- [Keyboard Shortcuts](keyboard-shortcuts.md) — the [`trigger:`](../dsl.md#trigger) grammar that could add Escape-to-close to this dialog.
- [`dismisses`](../dsl.md#dismisses--remove-from-the-dom) and the [presets table](../dsl.md#presets) in the DSL reference.
