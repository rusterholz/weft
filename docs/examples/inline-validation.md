# Inline Validation

A signup form's email field that checks itself: leave the field, and a moment later there's either a green all-clear or a specific complaint — straight from the server, before the user gets anywhere near the submit button.

This is Weft's take on [htmx's inline-validation example](https://htmx.org/examples/inline-validation/), and the shape is the same: the field posts its value when it changes, the server decides, and the field's corner of the page re-renders with the verdict. In Weft the field is a small component that owns its whole validation story — the check, the error state, and the success state live next to the markup they decorate.

## The components

```ruby
TAKEN_EMAILS = ["taken@example.com"].freeze

class SignupEmailField < Weft::Component
  builder_method :signup_email_field

  attribute :email
  attribute :error_message

  performs :validate, target: "#signup-email-field" do |attrs|
    email = attrs.email.to_s.strip
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      raise Weft::Unprocessable, "That doesn't look like an email address."
    end
    raise Weft::Unprocessable, "#{email} is already registered." if TAKEN_EMAILS.include?(email)

    nil
  end

  recovers from: Weft::Unprocessable do |_attrs, error|
    { error_message: error.message }
  end

  def build(attributes = {})
    super
    set_attribute :id, "signup-email-field"
    form(action: :validate, trigger: "change") do
      label "Email Address ", for: "email"
      input type: "email", name: "email", id: "email", value: attrs.email
    end
    if attrs.error_message
      para attrs.error_message, style: "color:#b91c1c"
    elsif attrs.email
      para "#{attrs.email} looks good.", style: "color:#15803d"
    end
  end
end
```

(The `TAKEN_EMAILS` list stands in for the uniqueness check your real data layer would run.)

## How it works

**The field is a component, and the form belongs to the field.** `form(action: :validate, trigger: "change")` wires the POST like any action form, but `trigger:` swaps the form's natural submit trigger for `change` events — which bubble up from the input, so the request fires the moment the user leaves the field. A form's fields are its payload: the typed email reaches the callable as `attrs.email`, exactly as it would on a full submit.

**Put the action on the form, not the input.** It's tempting to skip the form and hang `action: :validate, trigger: "change"` on the input itself. Don't: on a non-form element, `action:` carries the component's declared attributes along as `hx-vals`, and htmx gives those precedence over the triggering element's own value — so the request goes out with the *component's* stale idea of the email, never the fresh keystrokes. A one-field form is the honest wiring: what's in the field is what gets sent.

**Validation failures are still renders.** Bad input raises `Weft::Unprocessable`; the `recovers from:` block catches it and returns `{ error_message: error.message }`, which merges into the attrs for the re-render. The response goes out as a semantic `422 Unprocessable Content` whose body is this same component wearing its error paragraph. Valid input sails through to the `nil` return and renders the success line at a plain `200`. (The machinery is [the `recovers` chain](../error-handling.md#the-recovers-chain); the merge is [the callable contract](../dsl.md#the-callable-contract).)

**A value that changes can't anchor the DOM id.** Weft derives a component's DOM id from its first declared attribute — here that's the email itself, which would give the wrapper a different id on every render. So the component pins its own slot: `set_attribute :id, "signup-email-field"` fixes the wrapper's id, and `performs :validate, target: "#signup-email-field"` points the swap at that same anchor. (The same stable-slot idiom as [Bulk Update](bulk-update.md), for the same reason.)

**The field echoes what the user typed.** The swap replaces the whole component, input included, so `value: attrs.email` writes the submitted text back into the fresh input — without it, every complaint would also blank the field.

## On the wire

The initial render (or `GET /_components/signup_email_field`) — one field, its form listening for `change`:

```html
<div id="signup-email-field">
  <form hx-post="/_components/signup_email_field/validate" hx-target="#signup-email-field"
        hx-swap="outerHTML" action="/_components/signup_email_field/validate" method="post"
        hx-trigger="change">
    <label for="email">Email Address </label>
    <input type="email" name="email" id="email"/>
  </form>
</div>
```

Typing `not-an-email` and tabbing away posts `email=not-an-email`, and the answer is `422 Unprocessable Content` — the component re-rendered mid-complaint, the typed text still in the field:

```html
<div id="signup-email-field">
  <form ...>
    <label for="email">Email Address </label>
    <input type="email" name="email" id="email" value="not-an-email"/>
  </form>
  <p style="color:#b91c1c">That doesn&#39;t look like an email address.</p>
</div>
```

`taken@example.com` earns the other complaint the same way (`422`, "taken@example.com is already registered."), and `maria@example.com` comes back `200 OK` wearing the success line:

```html
  <p style="color:#15803d">maria@example.com looks good.</p>
```

And the part that makes it *inline*: a browser's `change` event on the input bubbles to the form and posts exactly what was typed — the captured request body is `email=typed.by.browser%40example.com`, no submit button involved.

## Related

- [Bulk Update](bulk-update.md) — the stable-slot idiom this page borrows, and reporting back through the returned hash.
- [Click to Edit](click-to-edit.md) — the basics of pairing form fields with declared attributes.
- [`performs`](../dsl.md#performs--user-initiated-actions), [`recovers`](../dsl.md#recovers--declare-error-behavior), and [`trigger:`](../dsl.md#trigger) in the DSL reference; [Error handling](../error-handling.md#the-recovers-chain) for the full recovery story.
