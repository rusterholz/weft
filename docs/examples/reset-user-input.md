# Reset User Input

An add-a-comment form beneath a comment list: submit, and the new comment appears in the list while the form comes back empty, ready for the next thought. Nothing *resets* the form — a new one arrives.

This is Weft's take on [htmx's reset-user-input example](https://htmx.org/examples/reset-user-input/), though "take on" oversells it. htmx needs `hx-on::after-request="this.reset()"` because the form that posted is still sitting in the DOM afterwards, holding the user's text. A Weft action re-renders the whole component from server state, so the swapped-in form never had text in it to begin with. There's nothing to do — this page is about why.

## The components

```ruby
GUEST_COMMENTS = [
  { author: "Rosa", body: "Lovely event — count me in for next year." }
]

class CommentSection < Weft::Component
  builder_method :comment_section

  attribute :author
  attribute :body

  performs :post do |attrs|
    author = attrs.author.to_s.strip
    body = attrs.body.to_s.strip
    GUEST_COMMENTS << { author: author, body: body } unless author.empty? || body.empty?
    { author: nil, body: nil }
  end

  def build(attributes = {})
    super
    ul do
      GUEST_COMMENTS.each do |comment|
        li { strong "#{comment[:author]}: "; text_node comment[:body] }
      end
    end
    form(action: :post) do
      div do
        label "Name ", for: "author"
        input type: "text", name: "author", id: "author"
      end
      div do
        label "Comment ", for: "body"
        input type: "text", name: "body", id: "body"
      end
      input type: "submit", value: "Add Comment"
    end
  end
end
```

(The `GUEST_COMMENTS` array stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**The response replaces the form, typed text and all.** `build` renders the list from the store and the inputs with no `value:` at all — so every render of this component has empty fields. The action's `outerHTML` swap replaces the old elements wholesale: the inputs holding the typed text leave the DOM, and fresh, empty ones arrive in the same response that shows the new comment in the list. What htmx solves with an after-request reset handler, the render model here dissolves.

**Clearing the params in the return keeps the identity stable.** The callable ends with `{ author: nil, body: nil }` — a returned hash merges into the attrs for the re-render ([the callable contract](../dsl.md#the-callable-contract)), and Weft derives a component's DOM id from its first declared attribute. Cleared, the wrapper comes back as the same `#comment-section` the htmx wiring points at; left populated, the submitted name would leak into the re-rendered component's identity.

**Blank submits are the callable's problem, and it handles them.** The browser happily posts `author=&body=`; the strip-and-check guard appends nothing, and the response is simply the current state re-rendered. Client-side `required` attributes would be a fine courtesy on top, but the server-side guard is the one that holds.

**No JavaScript, no reset handler.** `form(action: :post)` also emits plain `action`/`method` attributes, so without htmx the same POST works as a full-page form submit — and a freshly rendered page has empty fields for exactly the same reason the fragment does.

## On the wire

The initial render (or `GET /_components/comment_section`) — one comment in the list, the form's inputs carrying no `value` attributes:

```html
<div id="comment-section">
  <ul>
    <li><strong>Rosa: </strong>Lovely event — count me in for next year.</li>
  </ul>
  <form hx-post="/_components/comment_section/post" hx-target="#comment-section"
        hx-swap="outerHTML" action="/_components/comment_section/post" method="post">
    <div>
      <label for="author">Name </label>
      <input type="text" name="author" id="author"/>
    </div>
    <div>
      <label for="body">Comment </label>
      <input type="text" name="body" id="body"/>
    </div>
    <input type="submit" value="Add Comment"/>
  </form>
</div>
```

Typing a comment and submitting posts `author=Elena&body=See+you+there%21`, and the `200 OK` response is the same component with Elena's comment in the list — and the same valueless inputs as the initial render:

```html
  <ul>
    <li><strong>Rosa: </strong>Lovely event — count me in for next year.</li>
    <li><strong>Elena: </strong>See you there!</li>
  </ul>
  <form ...>
```

In a real browser the captured round trip reads the same: the POST body carries the typed values (`author=Browser%20Bot&body=Submitted%20by%20a%20real%20browser.`), and the post-swap DOM shows the new comment *and* empty inputs — the elements that held the typed text are gone, replaced by the response.

## Related

- [File Upload](file-upload.md) — clearing a param in the return for a different reason.
- [Click to Edit](click-to-edit.md) — when you *do* want fields pre-filled, pair them with declared attributes.
- [`performs`](../dsl.md#performs--user-initiated-actions) and [the callable contract](../dsl.md#the-callable-contract) in the DSL reference.
