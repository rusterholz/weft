# Keyboard Shortcuts

A component action fired by a keystroke from anywhere on the page — the same request a click would make, bound to a key combination instead. No new machinery: a keyboard shortcut is just another trigger.

This is Weft's take on [htmx's keyboard shortcuts example](https://htmx.org/examples/keyboard-shortcuts/), and the shape carries over directly: htmx's `hx-trigger` grammar already knows about key events, filters, and listening beyond the element itself, and Weft's [`trigger:`](../dsl.md#trigger) kwarg accepts that grammar in full.

## The components

```ruby
INBOX_NOTE = { archived: false }

class InboxNote < Weft::Component
  builder_method :inbox_note

  performs :archive do
    INBOX_NOTE[:archived] = true
    nil
  end

  def build(attributes = {})
    super
    if INBOX_NOTE[:archived]
      para "Archived. Nothing left to do here."
    else
      para %("Lunch on Thursday?" — from Sam)
      button "Archive (Alt+Shift+A)", action: :archive,
             trigger: "click, keyup[altKey&&shiftKey&&key=='A'] from:body"
    end
  end
end
```

(The `INBOX_NOTE` hash stands in for your data layer.)

## How it works

**`trigger:` accepts the full htmx grammar.** The semantic symbols in the [trigger table](../dsl.md#trigger-values) cover the common cases, but any string passes through to `hx-trigger` untouched — and that string can use everything [htmx's trigger syntax](https://htmx.org/attributes/hx-trigger/) offers. This one uses three pieces at once: *comma-separated triggers* (either one fires the request), an *event filter* in brackets (a JavaScript expression tested against the event), and a *`from:` modifier* (listen on `body`, not just the element).

**Two triggers, one action.** [`action:`](../dsl.md#action) supplies what the request *is* — the POST to `:archive`, the target, the swap. `trigger:` only changes *when* it fires, replacing the button's default click-only trigger with click-or-keystroke. The button stays a button; the shortcut is an alternative route to the identical request.

**`from:body` is what makes it a shortcut.** Without it, the keyup would only fire while the button itself had focus — which is no shortcut at all. Listening on `body` catches the key anywhere on the page. The filter then decides *which* keys: requiring `altKey && shiftKey` keeps the action from firing while someone merely types the letter into a text field. Bare-key bindings — `keyup[key=='/'] from:body` to jump to a search box, say — use the same grammar; just remember that unmodified letters and typing collide.

## On the wire

The initial render — one button carrying both the action wiring and the composite trigger:

```html
<div id="inbox-note">
  <p>&quot;Lunch on Thursday?&quot; — from Sam</p>
  <button hx-post="/_components/inbox_note/archive" hx-target="#inbox-note"
          hx-swap="outerHTML" hx-vals="{}"
          hx-trigger="click, keyup[altKey&amp;&amp;shiftKey&amp;&amp;key==&#39;A&#39;] from:body">
    Archive (Alt+Shift+A)</button>
</div>
```

The `&amp;&amp;` and `&#39;` are ordinary HTML attribute escaping — the browser decodes them before htmx reads the attribute, so htmx sees exactly the string you wrote: `click, keyup[altKey&&shiftKey&&key=='A'] from:body`.

Clicking the button — or pressing Alt+Shift+A anywhere on the page — issues `POST /_components/inbox_note/archive`, and the re-rendered component replaces the note:

```html
<div id="inbox-note">
  <p>Archived. Nothing left to do here.</p>
</div>
```

## Related

- The [trigger values table](../dsl.md#trigger-values) — the semantic symbols this page's raw string bypasses.
- [Active Search](active-search.md) — another interaction defined almost entirely by its trigger.
- [Modal Dialog](modal-dialog.md) — where the same grammar could bind Escape to a dismissal.
