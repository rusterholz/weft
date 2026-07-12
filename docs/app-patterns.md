# Application patterns

The [tutorial](tutorial.md) gets an app running, and the reference docs cover each mechanism on its own. This page is about the application *around* the components — where things live as a Weft app grows, and how the rest of your stack plugs in.

The theme throughout: Weft is deliberately small. It owns pages, components, and the wiring between user actions and renders. Everything else — your data, your background jobs, your authentication, your assets — is ordinary Ruby on ordinary Rack, and each has a well-defined seam.

## Laying out a growing app

The tutorial's layout extends naturally:

```
my-app/
├── config.ru
├── config/
│   └── environment.rb
├── app/
│   ├── components/
│   ├── data/          # stores, models, Current — your data layer
│   ├── pages/
│   └── services/      # business operations
└── spec/
```

`config/environment.rb` grows one entry in its load list:

```ruby
%w[data services components pages].each do |dir|
  Dir[File.join(APP_ROOT, "app", dir, "*.rb")].sort.each { |file| require file }
end
```

The ordering carries the same rule the tutorial explains: files that *define* things load before files that *reference* them in class bodies (`includes AttendeeList`, `transfers to: Confirmation`). Data and services never reference components, components reference each other and the data layer, pages compose components — so data → services → components → pages loads cleanly. When alphabetical luck within a directory stops being enough, that's the sign your app has outgrown the glob and wants a real autoloader like Zeitwerk.

## Where business logic goes

Components own what the user **sees and does** — the markup, the affordances, and the immediate response to an action. They should not own your business rules.

The dividing line runs through the action callable. A callable is a translation layer: attributes in, one operation invoked, a hash out for the re-render. The moment the middle step grows past a few lines — multiple records, a transaction, an email, a job — it belongs in a plain Ruby service object:

```ruby
# app/services/comment_poster.rb
class CommentPoster
  def self.call(author:, body:)
    author = author.to_s.strip
    body = body.to_s.strip
    return :blank if author.empty? || body.empty?

    GUEST_COMMENTS << { author: author, body: body }
    :posted
  end
end
```

```ruby
# in the component
performs :post do |attrs|
  CommentPoster.call(author: attrs.author, body: attrs.body)
  { author: nil, body: nil }
end
```

The service knows nothing about components or HTML; the component knows nothing about how a post actually happens. Two details worth noticing:

- **End the callable with the hash you mean.** A callable's return value merges into the attributes for the re-render *if it's a hash* — anything else is discarded (see [the callable contract](dsl.md#the-callable-contract)). Delegating to a service and then returning your own hash, as above, keeps the wire state deliberate even when the service's return value changes.
- **The service returns plain Ruby values** (`:posted`, `:blank`, a record, a result object — whatever fits). When the component needs to branch on the outcome, branch in the callable and translate to attributes; the service still shouldn't know what a DOM id is.

## Databases

Weft has no data layer and no ORM opinion. `build` methods and callables are plain Ruby, so `Event.find(...)`, `DB[:events].where(...)`, and a hand-rolled store are all the same to Weft — the examples' data-constant stubs stand in for whichever you choose. ActiveRecord in standalone mode, Sequel, ROM, or a bare adapter are all equally at home; establish the connection in `config/environment.rb` before the app files load, and your components can use it from the first render.

One operational honesty about the in-memory stores the tutorial and examples use: module-level state is **per-process**. That's exactly right for learning and development, and exactly wrong under a multi-process server — each Puma worker gets its own copy, and they drift immediately. The moment state needs to be shared or survive a restart, it belongs in a real database (or Redis, or any store that lives outside the app process).

## Background jobs

Weft doesn't run jobs, but it has a natural shape for showing their progress: **a job writes to the store; a component watches the store**.

The pattern in three steps:

1. **The action dispatches and returns.** A user action that starts long work shouldn't wait for it — the callable enqueues the job (Sidekiq, SolidQueue, GoodJob, a `Thread` in development — Weft doesn't care) and returns immediately with whatever attributes render the "started" state.
2. **The job writes progress to the shared store** as it works: a status column, a percentage, a result row. The job knows nothing about components.
3. **The component re-renders on a cadence** — [`refreshes every:`](dsl.md#refreshes--the-client-re-fetches) polls, [`pushes every:`](dsl.md#pushes--the-server-sends-updates) streams over SSE — and each render just reads the store. Completion isn't an event to handle; it's data the next render picks up.

The [Progress Bar](examples/progress-bar.md) example is this exact lifecycle, verified end to end — a Start action kicking off a background worker, a polling component advancing as the store changes, a finished state with a Restart affordance. [Live Ticker](examples/live-ticker.md) is the SSE variant. Both pages show precisely what travels on the wire.

## Authentication and sessions

Weft is deliberately session-agnostic: no cookie handling, no `current_user`, no login machinery. Identity is your app's concern, handled with standard Rack pieces in front of the Router. What Weft *does* define is the seam, and it's narrower than you might expect:

> Components and callables receive exactly their **resolved attributes** — values from request parameters, filtered through each component's declared schema. Session state and request headers are not part of that channel.

So per-request identity needs its own channel. The pattern that fits — the same one Rails blesses as `Current` — is a [`CurrentAttributes`](https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html) object set by middleware. Weft already depends on ActiveSupport, so it's available without adding anything:

```ruby
# app/data/current.rb
require "active_support"
require "active_support/current_attributes"

class Current < ActiveSupport::CurrentAttributes
  attribute :user, :csrf_token
end
```

(The bare `require "active_support"` line matters: requiring only `current_attributes` fails on recent ActiveSupport versions, which expect the framework's base to be loaded first.)

A small middleware reads the session once per request, exposes it through `Current`, and — importantly — always resets afterwards, so state never leaks between requests on a reused thread:

```ruby
class CurrentScope
  def initialize(app)
    @app = app
  end

  def call(env)
    session = env["rack.session"]
    Current.user = session["user"]
    Current.csrf_token = Rack::Protection::AuthenticityToken.token(session)
    @app.call(env)
  ensure
    Current.reset
  end
end
```

Session *writes* — logging in and out — live outside Weft components, in any Rack endpoint you own. A tiny Sinatra app is plenty, mounted beside the Router:

```ruby
class AuthApp < Sinatra::Base
  post "/login" do
    session["user"] = params["name"]
    redirect "/", 303
  end

  post "/logout" do
    session.delete("user")
    redirect "/", 303
  end
end
```

`config.ru` assembles the stack — session first, then protection, then `CurrentScope`, then the apps:

```ruby
require_relative "config/environment"
require "rack/session"
require "rack/protection"
require "sinatra/base"

use Rack::Session::Cookie, secret: ENV.fetch("SESSION_SECRET")  # 64+ characters
use Rack::Protection::AuthenticityToken
use CurrentScope

map "/auth" do
  run AuthApp
end

run Weft::Router
```

From there, any component can read identity like any other Ruby value:

```ruby
class WhoAmI < Weft::Component
  builder_method :who_am_i

  def build(attributes = {})
    super
    if Current.user
      para "Signed in as #{Current.user}."
      form(action: "/auth/logout", method: "post") do
        input type: "hidden", name: "authenticity_token", value: Current.csrf_token
        input type: "submit", value: "Sign out"
      end
    else
      para "You're browsing anonymously."
      form(action: "/auth/login", method: "post") do
        input type: "hidden", name: "authenticity_token", value: Current.csrf_token
        label "Name ", for: "name"
        input type: "text", name: "name", id: "name"
        input type: "submit", value: "Sign in"
      end
    end
  end
end
```

Note the form lines: `action:` with a **string** renders as a plain HTML `action` attribute — an ordinary full-page form post to your auth endpoint, no htmx involved. It's only `action:` with a **symbol** that wires up a Weft component action. The two coexist naturally: identity changes full pages; component actions swap fragments.

(This example stores the user's name in the session directly to stay small; a real app stores an id and has `CurrentScope` — or a lazy reader on `Current` — hydrate the user record.)

Authorization follows the same grain: middleware can gate whole path prefixes before Weft ever sees the request, and components can branch on `Current.user` to decide which affordances to render. For anything destructive, check authority *in the action's service call* too — component actions are plain HTTP endpoints, and markup you didn't render is not a guarantee nobody sends the request.

## CSRF protection

The stack above already includes it. `Rack::Protection::AuthenticityToken` (part of rack-protection, which ships with Sinatra) rejects any non-GET request that doesn't carry a valid token — **including every Weft action form**, since those are ordinary POSTs. Two pieces make it work:

1. `CurrentScope` computes the session's token via `Rack::Protection::AuthenticityToken.token(session)` and exposes it as `Current.csrf_token`.
2. Every form gains one hidden input:

```ruby
input type: "hidden", name: "authenticity_token", value: Current.csrf_token
```

That covers both transports at once: the htmx path (a form's fields are its payload) and the no-JS fallback submit carry the same field. A missing or stale token is a `403` before the request reaches any component; with the token, actions behave exactly as before. Weft has no form helper to inject this automatically today, so the hidden input is per-form — a base component class of your own is a fine place to fold it into a one-liner.

## Assets

The seam is [`static_assets`](configuration.md#static_assets): register a directory as a named bundle, and `register_stylesheet` / `register_script` resolve bare-relative paths against it. Whatever produces the files — esbuild, Vite, Tailwind's CLI, Sprockets, or a `cp` in your Makefile — Weft only needs to know the output directory:

```ruby
Weft.configure do |c|
  c.static_assets root: "/assets", from: File.join(APP_ROOT, "public/assets")
end
```

Point your bundler's output at that directory and the integration is done. The [configuration reference](configuration.md#static_assets) covers multiple bundles, environment-specific roots, and the resolution rules.

## Testing the whole app

[Component unit testing](arbre.md#testing-components) needs no server: `Component.render(**attrs)` returns the HTML string. For request-level coverage — routes, actions, status codes, wire payloads — use Rack::Test against the Router:

```ruby
# spec/spec_helper.rb
ENV["RACK_ENV"] ||= "test"

require "rack/test"
require_relative "../config/environment"

RSpec.configure do |config|
  config.before(:each) do
    GUEST_COMMENTS.replace([{ author: "Rosa", body: "Lovely event — count me in for next year." }])
  end
end
```

```ruby
# spec/router_spec.rb
RSpec.describe "the app through Weft::Router" do
  include Rack::Test::Methods

  def app = Weft::Router

  it "serves a component fragment" do
    get "/_components/comment_section"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Rosa")
  end

  it "runs an action" do
    post "/_components/comment_section/post", author: "Test", body: "From a spec."
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Test")
  end
end
```

Two lines in that helper do quiet, load-bearing work:

- **`ENV["RACK_ENV"] ||= "test"`.** Without it, specs run in Sinatra's development mode, whose DNS-rebinding host protection rejects Rack::Test's default host — every request comes back `403 Host not permitted` before reaching your app. The test environment permits it.
- **The `before(:each)` reset.** Weft doesn't own your data layer, so state between examples is your responsibility — replace the in-memory store's contents, truncate tables, or run each example in a transaction, per your data layer's usual practice.

These specs hit `Weft::Router` directly, bypassing whatever middleware `config.ru` stacks in front — which is usually what you want when the subject is component behavior. (It's also why the action POST above needs no CSRF token: the protection middleware isn't in the loop.)

## Where to go from here

- [The examples catalog](examples/README.md) — worked patterns with captured wire traffic, including the [Progress Bar](examples/progress-bar.md) job lifecycle.
- [The Weft DSL](dsl.md) — the callable contract, every verb, every kwarg.
- [Routing](routing.md#mounting-the-router) — standalone vs. middleware mounting in detail.
- [Configuration](configuration.md) — static assets, reloading, error presentation.
