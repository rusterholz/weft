# Development Guide

Setting up a development environment for working on weft, running the test suites, and releasing new versions.

## Setup

After checking out the repo, run `bin/setup` to install dependencies, then `bundle exec rake spec` to run the tests. `bin/console` gives you an interactive prompt with the gem loaded.

## Running Tests

**Gem suite** — fast, no external dependencies:

```bash
bundle exec rspec                            # the whole suite
bundle exec rspec spec/weft/router_spec.rb   # one file
```

**Dependency matrix** — weft supports Arbre 1.7 and 2.2 across ActiveSupport 6.1–8.0. [Appraisal](https://github.com/thoughtbot/appraisal) runs the suite against each pinned combination:

```bash
bundle exec appraisal install   # once, and again after dependency changes
bundle exec appraisal rspec     # the full six-gemfile matrix
```

Run the matrix before committing any gem code change — a construct that works on current ActiveSupport can still break the oldest row.

**Demo suite** — the demo app (`demo/`) has its own Gemfile and specs:

```bash
cd demo
bundle exec rspec
```

Demo specs come in two kinds. Most are `type: :component` and render one class in isolation
through the `render_weft` / `render_weft_html` helpers. Specs under `spec/requests/` are
`type: :request` and drive `Weft::Router` end to end with `Rack::MockRequest` (bundled with
Rack — no extra gem), which is the only way to assert a whole response: the primary render, the
out-of-band companions riding with it, the status, and the `HX-*` headers together. `weft_get` /
`weft_post` and a `count_selects` query counter live in `spec/support/request_helper.rb`.

## The Demo App

`demo/` is a full Sinatra + ActiveRecord app ("Dropship Co.") built on weft — both a showcase and the top of the testing pyramid. A clockwork process simulates a live order pipeline under a puma server:

```bash
cd demo
bundle exec rake dev:up        # reset the DB, start clockwork + puma on :9292
bundle exec rake dev:restart   # bounce everything after code changes
bundle exec rake dev:down      # stop everything
bundle exec rake check         # rspec + rubocop — what CI runs
```

When a gem change touches request handling, rendering, or the DSL, exercise the demo live; the error-drills page (`/drills`) walks every recovery pathway.

## Linting

```bash
bundle exec rubocop
```

Both the gem and the demo (`cd demo && bundle exec rubocop`) must be offense-free.

## Documentation Drift

Prose has no compiler, so a rename lands, the specs go green, and the docs keep confidently naming a method that no longer exists. `bin/doc-drift-check` catches the mechanical half of that:

```bash
bundle exec bin/doc-drift-check   # all four checks
bin/doc-drift-check               # links + identifiers only, no gem load
```

It verifies that intra-repo links and anchors resolve, that identifiers presented as methods exist, that every gem-level setting the docs name on `Weft` (`Weft.configure` and friends) answers on the real namespace, and that keyword arguments in ruby examples match the DSL's actual signatures. It exits non-zero on any finding — run it whenever you change docs or rename anything the docs describe.

Two categories are *derived* rather than allowlisted, so the check stays honest as the docs grow: Arbre's builder surface comes from `Arbre::Element`'s own ancestors, and component builders come from every `builder_method` the docs declare. A misspelled builder call still fails, which is the point.

What it cannot ask is whether a paragraph is still *true* — a characterization outlives the design it described far more quietly than a method name does. That judgment stays yours.

## Lockfiles and Platforms

After changing the `Gemfile`, `Appraisals`, or the gemspec:

```bash
bundle install                      # or bundle exec appraisal install for Appraisals changes
bundle exec rake gemfile:platforms  # re-adds the ruby/darwin/linux platform variants
bundle exec rubocop -a Gemfile.lock gemfiles/
```

Bundler operations tend to drop platforms from lockfiles; the rake task restores them idempotently, and CI's Linux runners depend on it.

## Require Hygiene

Every file under `lib/` declares its own requires rather than leaning on load order, so each must load standalone:

```bash
for f in $(find lib -name "*.rb" | sed 's|^lib/||; s|\.rb$||'); do
  bundle exec ruby -e "require \"$f\"" || echo "FAIL: $f"
done
```

The gem root must also cold-load on the oldest dependency row:

```bash
BUNDLE_GEMFILE=gemfiles/arbre_1.7_as_6.1.gemfile bundle exec ruby -e 'require "weft"'
```

## CI

Every push runs `.github/workflows/ci.yml`: a lint job (RuboCop), the Appraisal matrix across the supported Ruby versions on Ubuntu and macOS, the demo's `rake check`, and a final gate job that requires all of them green.

## Gem File Contents

The gemspec builds its file list from an explicit glob (`lib/`, `docs/`, README, CHANGELOG, LICENSE) and excludes maintainer docs like this file. Before each release, audit what ships:

```bash
bundle exec rake build          # outputs to pkg/, which is gitignored
gem unpack pkg/weft-X.Y.Z.gem && ls -R weft-X.Y.Z/
```

## Releasing a New Version

Tags are created on `main` only — finish the work, merge, then release from a clean checkout.

1. Audit the gem file contents (above).
2. Bump `lib/weft/version.rb` and date the CHANGELOG entry.
3. Full verification: gem suite, Appraisal matrix, demo suite, RuboCop, require hygiene.
4. Commit and merge to `main`.
5. From clean `main`: `bundle exec rake build`, inspect the output, then `gem push pkg/weft-X.Y.Z.gem`.
6. Tag: `git tag vX.Y.Z && git push --tags`.
