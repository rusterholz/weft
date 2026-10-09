# The Request

Every component and page can read the request it renders for. `params` holds the values the request sent, validated and coerced; `request` holds everything else about it: who sent it, what headers came with it, what htmx was doing at the time, and an id that names the request, which every response Weft answers carries back.

```ruby
class OrderCard < Weft::Component
  param :order_id
  identifies_by :order_id

  def build(attributes = {})
    super
    div(class: "order-card") do
      h3 "Order #{params.order_id}"
      para "Opened from #{request.htmx.current_url}" if request.htmx?
    end
  end
end
```

`request` is a `Weft::Request`. You reach it the same way you reach `params`, with the same guarantees: it's there in `build`, in any private method `build` calls, and inside the element blocks you nest, and it's never `nil`. A component pushed over a stream reads the request that opened the stream, so every push answers to the same id.

Blocks you hand to Weft (`performs`, `derives`, `recovers` and the rest) don't receive the request yet. That's coming next; until then, read it from `build`.

## Headers

`header` reads a request header by its HTTP name, in any case, and `header?` says whether it came at all:

```ruby
request.header("Authorization")   # => "Bearer abc123", or nil
request.header?("X-Forwarded-For") # => true
```

There's no Rack `HTTP_` prefix to remember: `header("Content-Type")` and `header("X-Api-Key")` both work as written.

## htmx

`request.htmx?` is true when htmx made the request. `request.htmx` reads the headers htmx sends along with it, and each answers `nil` (or `false`) on a request htmx didn't make:

| Reader | Header | Answers |
| --- | --- | --- |
| `request.htmx.target` | `HX-Target` | the id of the element being swapped into |
| `request.htmx.trigger` | `HX-Trigger` | the id of the element that triggered the request |
| `request.htmx.trigger_name` | `HX-Trigger-Name` | that element's `name` attribute |
| `request.htmx.current_url` | `HX-Current-URL` | the browser's URL at the time |
| `request.htmx.prompt` | `HX-Prompt` | what the user typed into an `hx-prompt` dialog |
| `request.htmx.boosted?` | `HX-Boosted` | whether a boosted link or form sent it |
| `request.htmx.history_restore?` | `HX-History-Restore-Request` | whether htmx is restoring a page its history cache missed |

## The Request Id

Every request has an id, and every response Weft answers carries it back in an `X-Request-Id` header, so the id in the browser's network tab is the one your code reads as `request.id`.

```ruby
request.id # => "6f1c0a52-8d3e-4b7a-9c21-0e5f2d7b9a14"
```

Weft takes the first of these it finds:

1. an id something in front of Weft already placed in the Rack env under `weft.request_id`;
2. the `X-Request-Id` header your proxy or load balancer sent, with anything but letters, digits, `_`, `-` and `@` stripped, and capped at 255 characters;
3. a fresh UUID.

Whichever it is, Weft writes it to `env["weft.request_id"]`, so Rack middleware and apps sharing the request see the same one. A response that already set its own `X-Request-Id` keeps it. When Weft runs as middleware and passes a request on to the app behind it, the id is waiting in the env, and the response is that app's to label.

Weft's own log lines don't carry the id yet.

## Plain HTTP

Beneath the htmx layer, the request answers the questions any HTTP request does:

- **Method:** `request_method`, `get?`, `post?`, `put?`, `patch?`, `delete?`, `head?`, `options?`, `safe?`, `idempotent?`, `xhr?`
- **Location:** `path`, `fullpath`, `url`, `base_url`, `scheme`, `secure?`, `host`, `port`, `referer`, and their relatives
- **Content:** `content_type`, `media_type`, `content_charset`, `content_length`
- **Negotiation:** `accept`, `accept?`, `preferred_type`, `accept_encoding`, `accept_language`
- **The client:** `cookies`, `user_agent`, `ip`, `forwarded_for`, `forwarded_authority`, `trusted_proxy?`

**Know your trust boundary before you trust `ip`.** It reads past `X-Forwarded-For` through every proxy Rack considers trusted, which by default means private and loopback addresses. A client can send that header too, so `ip` names the real client only when everything in front of your app is one you control. `request.trusted_proxy?` takes an address and answers whether Rack would trust that hop, so code that rate-limits or locks accounts can decide for itself.

Setting cookies is the response's job, not the request's.

## What It Leaves Out

The request has no `params`, no `GET` or `POST`, no `body` and no `query_string`. What a request sends reaches your code through `params`, validated, coerced and ranked.

`request.env` is still there, for anything the readers above don't cover. Values you read from it are raw, exactly as Rack received them.

Sessions aren't on the request yet.

## Logging

`request.logger` is `Weft.logger`, the same object, so a component can log without reaching for a global:

```ruby
request.logger.info("rendering #{self.class.name}")
```

## Rendering With A Request

`Component.render` and `Page.render` take the wire and the request, both, every time:

```ruby
OrderCard.render({ order_id: "42" }, nil)
OrderPage.render({ tab: "items" }, Rack::MockRequest.env_for("/orders/42"))
```

The request can be a Rack env, a Rack or Sinatra request, a `Weft::Request`, or `nil` for an empty one: a GET for `/` that sent nothing. The wire is layered over whatever the request sent, so a spec can set up a request once and vary one value per example. A page takes its route's params from the request's path, by matching its own `page_path`. [Testing components](arbre.md#testing-components) has the rest, including the kwargs and content block a builder call would pass, and `render_element` for the element tree.
