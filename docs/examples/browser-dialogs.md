# Browser Dialogs

A destructive button guarded by the browser's native `confirm()` dialog — the user gets a chance to back out before the request is ever made, with no dialog component to build and no CSS to write.

This is Weft's take on [htmx's dialogs example](https://htmx.org/examples/dialogs/). The honest point of this page is that Weft has no kwarg for `hx-confirm` — and doesn't need one: raw htmx attributes pass through to the element untouched, side by side with whatever the Weft kwargs expand to.

## The components

```ruby
ACCOUNT = { status: "active" }

class AccountPanel < Weft::Component
  builder_method :account_panel

  performs :deactivate do
    ACCOUNT[:status] = "deactivated"
    nil
  end

  def build(attributes = {})
    super
    para "Your account is #{ACCOUNT[:status]}."
    if ACCOUNT[:status] == "active"
      button "Deactivate my account", action: :deactivate,
             "hx-confirm" => "Deactivate your account? You can sign back in to reactivate."
    end
  end
end
```

(The `ACCOUNT` hash stands in for your data layer, and the current user for whoever your app has signed in.)

## How it works

**Raw htmx attributes ride along.** Weft intercepts only its own kwargs — `action:`, `trigger:`, and friends. Everything else on an element, string-keyed htmx attributes included, renders as a plain HTML attribute. So `"hx-confirm" => "..."` lands verbatim next to the wiring that [`action:`](../dsl.md#action) expanded, and htmx picks it up like any hand-written page. This is the general escape hatch: whenever htmx has a feature Weft has no vocabulary for, write the attribute yourself.

**The guard lives in the browser, not on the server.** `hx-confirm` gates the *request*: htmx shows the native dialog and only issues the POST if the user accepts. The endpoint itself is unchanged — a request made outside htmx skips the question entirely. Treat it as protection against misclicks, never as access control; anything truly destructive still needs authorization server-side.

**The action is ordinary Weft.** `performs :deactivate` runs the write and re-renders the component, which now shows the deactivated state — the standard action contract, unaware that a dialog ever happened.

**`hx-prompt` doesn't carry over.** htmx's companion attribute asks for a line of text and sends the answer as an `HX-Prompt` *request header* — but a Weft action callable receives only the component's resolved attributes, which come from request parameters, so the prompted value never reaches your code. When an action needs user input, give the component a real input: a form field paired with a declared attribute, as in [Click to Edit](click-to-edit.md).

## On the wire

The initial render — the confirm attribute sits verbatim beside the expanded action wiring:

```html
<div id="account-panel">
  <p>Your account is active.</p>
  <button hx-confirm="Deactivate your account? You can sign back in to reactivate."
          hx-post="/_components/account_panel/deactivate"
          hx-target="#account-panel" hx-swap="outerHTML"
          hx-vals="{}">Deactivate my account</button>
</div>
```

Accepting the dialog issues `POST /_components/account_panel/deactivate`, and the re-rendered panel replaces the old one:

```html
<div id="account-panel">
  <p>Your account is deactivated.</p>
</div>
```

The same POST sent from outside the browser — no htmx, no dialog — is accepted just the same, which is exactly why the confirm is a courtesy and the authorization is your job.

## Related

- [Modal Dialog](modal-dialog.md) — when you want a dialog you own instead of the browser's.
- [Click to Edit](click-to-edit.md) — form fields paired with attributes: the Weft answer to "prompt the user for a value."
- [`action:`](../dsl.md#action) and [`performs`](../dsl.md#performs--user-initiated-actions) in the DSL reference.
