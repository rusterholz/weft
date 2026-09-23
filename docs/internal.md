# Internals

Notes for people working **on** Weft rather than with it. Nothing here is public API; everything here
is something you have to know before changing how params reach a component.

This file is written per-area as areas are worked on, so it is deliberately incomplete. What is here
is true; what is missing is missing, not implied.

## Two words, used precisely

Bags are made in two different ways, and the distinction carries most of this document.

**Assembling** is making a bag from nothing — no parent. It happens at the handful of places a request
first needs one: the top of a component render, an action, a stream frame, a page failure, and the
public class-level entry that has to accept a plain hash. Five sites, and that is the whole list.

**Branching** is making a bag from another bag, and it is by far the common case. It comes in two kinds:

- a **crossing** branch enters another component's declarations, so it re-resolves the wire, coerces,
  re-homes thunks, and demotes everything it inherits to level 4. Every component in a render tree gets
  its bag this way, from its nearest ancestor's.
- a **non-crossing** branch (`bag % delta`) keeps the same declarations and layers a delta on top.
  Nothing demotes, nothing re-resolves.

What separates them is the travel rule below: **a crossing branch demotes; a non-crossing branch does
not.** That is why they are two operations rather than one with a flag, and why `bag % {}` is not the
same thing as a crossing branch back into the bag's own class.

*(One residue to know about: the class that implements both is called `Params::Assembly`, and its
`branched_from:` keyword is what selects between them. The name predates the distinction.)*

## The params source stack

A component's params bag is composed once, when the branch into that component is taken, from six
ranked sources. The first one that answers for a key wins.

| # | level | supplied by |
|---|-------|-------------|
| 1 | **hand-off** | a `receives` value staged by the call site that built this component, or one an ancestor was handed |
| 2 | **overlay** | a delta returned by a verb block, applied to this render's root |
| 3 | **own wire** | this class's declared params, resolved and coerced from the request |
| 4 | **inherited** | the branch copy of the nearest tree-ancestor's bag |
| 5 | **derivation** | a `derives` / `defines` block, held unforced as a thunk |
| 6 | **default** | the `default:` on the declaration |

The ranking is *specificity to me*: a value someone computed expressly for this component outranks one
it merely found lying around.

**Levels 1–5 are composed in `Params::Assembly#stack_value`; level 6 lives in `Params#[]`.** That split
is not cosmetic. A default is a property of the *class*, so it must answer even for a bag assembled
where no call site ran — which is why it is consulted at read time against `@defaults` rather than
baked into the composed data.

### Two behaviors worth knowing before you touch this

**An overlay of `nil` suppresses own-wire.** Level 2 and level 3 collapse into a single expression, and
the test is key-presence, not nil-ness:

```ruby
@overlays.key?(key) ? @overlays[key] : @wire[key]
```

So an overlay carrying `{status: nil}` does *not* blank the key and does *not* fall back to the wire —
it discards the wire value and resolution continues at level 4. Observable, where `%` applies a delta
to a bag:

```ruby
Assembly.call(klass, {status: "from-wire"}, branched_from: ancestor)[:status]
# => "from-wire"
Assembly.call(klass, {status: "from-wire"}, branched_from: ancestor % {status: nil})[:status]
# => "from-ancestor"
```

Which is why a nil in a delta reaches the overlay but never the data. It is an instruction to suppress
a wire value rather than a value of its own, and writing it into the data would erase the very entry
resolution is being asked to fall through to — the ancestor's, in the example above.

**Undeclared keys ride the bag wholesale.** `Assembly#bag` seeds itself from the inherited hash and
*then* overwrites the declared keys:

```ruby
data = @inherited.dup
keys.each { |key| data[key] = stack_value(key) }
```

A component that declares nothing therefore still reads its ancestors' keys. This is deliberate and
worth understanding rather than tidying: the classes obliged to declare are exactly the ones that can
be addressed independently, because a component declaring nothing is not routable. A convenience class
that only ever renders inside its parent pays nothing.

It has three costs a maintainer should be able to name: the class stops documenting its own inputs; it
breaks on reparenting, and breaks as a bare `NoMethodError` rather than an explanation; and the key
never rides that component's own URLs, since serialization projects the class's declared params only —
correct today, a trap if the class later becomes routable.

Inherited values **are** coerced. Coercion runs when the branch is taken, not at read time, so a value
does not lose its type by crossing a branch.

### `override:`

A derivation declared `override:` lifts above **inherited only** — it does not outrank a hand-off, an
overlay, or the component's own wire. The intent is "I always compute this myself rather than accepting
my parent's copy," not "I win."

`defines` registers with `override: true` always, which is the one behavior it does not share with the
`derives` it is sugar for. A derivation defaults to yielding because it is a standalone fallback; a pin
exists precisely to fix a value an ancestor also supplies, so a yielding pin could not do its only job.

### The transmitted slots, and why a bag holds them

A bag is `(data, overlay, handoff, defaults, owner)`. The overlay is the accumulated verb-block delta
and the handoff is the accumulated `receives` values; both are held apart from the data because they
travel differently from it. Data demotes to "inherited" when a branch crosses into another component's
declarations, while these two persist at their own rungs all the way down. A bag holding only the merged
result could not express that difference — and for a long time weft's could not, which is where the
delta's rung came from and where it went wrong.

The rule the two slots share: **a value gets a transmitted slot when its rank has to survive a
crossing.** Data carries reach, a slot carries rank. Both of these authorities were applied
deliberately by someone (a verb block returning a key, a call site staging one) and are scoped to a
subtree, which is what earns them the slot; a value a component merely resolved for itself was nobody's
deliberate statement about anything below it, and demotes.

`bag % delta` applies a delta. It writes the delta's **values** to the data, which is what the bag
answers with, and the **whole delta** to the overlay, which is what the next crossing branch re-applies
at level 2. Those are two jobs rather than one: what a bag *answers* and what it *passes down* are
different questions, and the hand-off case is where the difference shows. A component with a `receives`
value and a delta on the same key answers with the hand-off, because level 1 outranks level 2, while
still transmitting the delta to everything below it.

So a read consults the data alone. The delta is already accounted for there — the crossing branch
ranked it at level 2, and `%` wrote its values straight in. Consulting the overlay again at read time
would re-apply level 2 on top of a finished result and quietly beat level 1.

`%` carries the handoff slot across untouched, which nothing in the Router exercises today: every call
site applies a delta to a root's bag, and a root has no hand-offs staged for it. It is there because an
operation on a bag that dropped one of the bag's own members is precisely the defect the slots exist to
prevent, and one spec holds it in place.

`bag % {}` returns **the same instance**, which lets a call site apply a delta unconditionally without
paying for a copy. That identity is safe only because **a bag has no writers**: a read forces a Thunk,
and the Thunk memoizes on itself rather than on the bag. Keep it that way — the moment a bag can be
mutated, every shared identity becomes an aliasing bug.

> The general lesson outlived the bug that taught it: **if an invariant lives only in the code that
> builds a value and not in the value itself, every later operation on that value silently discards
> it.** The delta used to be ranked only while a bag was being composed, so every operation afterwards
> could merge it into the data and nothing could tell that its rung had been lost.

## Lineage

Every root a request builds carries a lineage edge — a parent bag, and a delta applied over it.
Recovery renders included; there are no orphans.

State the invariant as **one lineage, never one bag.** A recovery or companion block *returns a delta*
that rides over the render's bag, so the block and the render below it hold the same bag only when that
delta happens to be empty. "One bag" claims something the code cannot promise and goes false the moment
a block does its job.

A branch copy is thunk-preserving and nil-dropping: `branch_data` is the bag's data compacted, so an
ancestor's unforced derivations cross as unforced twins rather than being forced to cross.

### What crosses a branch

Ranking is *per component*, so a descendant cannot inherit its ancestor's internal ordering — from its
seat, every entry in an ancestor's bag has identical provenance: *someone above me resolved this*.
Preserving the ancestor's ranking would make a child's resolution depend on how its parent happened to
obtain a value, and would multiply the stack with depth.

The table is about **rank**, not reach. Everything in a bag except a declared default reaches every
component below it; what varies is the level it speaks at when it gets there.

| what | on crossing a branch |
|------|----------------------|
| a declared `default:` | **does not cross at all** — which is why a child's own default is sovereign |
| own wire values, resolved values, thunks | **arrive, demoted** to level 4, "inherited" |
| a hand-off (`receives`) | **arrives at its own rank**, level 1, accumulating per key as it descends |
| an applied delta (the overlay) | **arrives at its own rank**, level 2, at every depth below |

An overlay's authority is **subtree-scoped**: it reaches the bag it was applied to and everything below
it, and nothing else. Two companions of one primary hold *different* overlays for the same key while
sharing one request. There is no request-wide params override, deliberately — a branch cannot modify
its siblings, which is what keeps universes consistent.

The one genuinely request-scoped params concept is the **wire universe** (below), and it never occupies
a rung at all.

### Hand-offs keep their rank

A `receives` value is the second thing a bag transmits at its own rung, alongside the overlay. Both
reach the whole subtree, and both keep the level they speak at the whole way down.

Reach and rank are still worth holding apart, because the words for them slur together and because a
declared default is the case where they come apart:

- **Reach** is which components can see the value at all. A hand-off's reach is the subtree, exactly
  like any other resolved value: a `StatusCard` handed `status:` passes it to the badge it builds
  inside, and two cards on one page each supply their own. Nothing would work otherwise, since the wire
  is usually empty for a key that arrives by hand-off.
- **Rank** is which level the value speaks at once it gets there. A hand-off speaks at level 1 at every
  depth, as an overlay speaks at level 2 at every depth. A declared default, by contrast, has no reach
  past its own class at all.

So a nested component that declares `param :status` reads its ancestor's hand-off rather than the
request's own value for that key. What a call site said expressly about that card outranks what the
page happened to be filtered by. Anything else breaks a collection: four cards built from four statuses,
each rendering a badge that declares the key, would all read the page's filter, resolve one identity
between them, and collide on a single DOM id.

The slot **accumulates on the way down**. Each crossing branch merges whatever its call site staged over
the hand-offs already in force, per key, so the nearest call site wins while keys nobody nearer
mentioned keep the ancestor's value. That is how a card overrides one child without disturbing the rest
of its subtree. A staged `nil` steps aside: it clears the inherited hand-off, and resolution continues
at the component's own wire. Note that this is the mirror image of a nil overlay, which suppresses the
wire and continues at inherited. Both mean "step aside," they step aside from different things, and the
two are easy to unify wrongly.

**Independent addressability survives, which is the objection this design has to answer.** A component
addressed on its own is a root: there is no ancestor, hence no hand-off, and its own wire wins exactly
as it always did. The cost is narrower than it first appears, and it is a real cost: while nested under
an ancestor holding the same key, a component cannot read the request's value for that key. Keys are a
flat namespace, so a component that wants the page's filter regardless of where it sits wants a key of
its own name rather than the one its ancestors pass around.

What is one-shot is the **staging register**, not the value. `Context#stage_received` holds one entry,
class-checked, and `take_received!` clears it, which is what stops the *next sibling* from picking up a
hand-off meant for its neighbor. The register's only job is getting the value into the right bag; the
slot is what carries it onward from there.

## Render-time scopes

Three lifetimes, and conflating them is the most common way to break this area.

| scope | lives for | holds |
|-------|-----------|-------|
| **per-delivery** | one delivered swap-set | the wire universe, the slot register |
| **per-root** | one root element tree | the branch bag, and the overlay riding on it |
| **per-tree** | one element tree | the DOM ids already emitted |

**The wire universe is everything the client sent** — the request's params minus routing internals,
undeclared keys included. A component's `@wire` is the *projection* of that universe through its own
declarations: wide source, narrow projection, narrowed per component. That is why an undeclared key
never reaches a bag through the wire door.

The universe never occupies a rung, because inheritance moves values and a source is not a value. It is
handed to each branch as an argument from the render environment, so a root with no lineage whatever
still has the whole of it.

> **Stated intention, not current structure:** the per-delivery members are hand-threaded today. They
> are intended to move onto a single object owned by the delivery, read directly rather than passed —
> which also collapses the repeated recomputation of the universe into one value. No such object exists
> yet; do not write code that assumes one.

"Cross-branch" names nothing in this system. Siblings share an ancestor and have no channel between
them; the only way one value reaches two siblings is by sitting in their common ancestor's bag or
overlay.

## The sandbox

Verb blocks run against a **void context** — a fresh `DSL::Sandbox` instance, empty of anything
component-specific, so a block cannot reach local state and is portable to any process:

```ruby
def self.run(...) = new.instance_exec(...)
```

Freshness rather than freezing is what isolates them: an instance is deliberately unfrozen, so a block
may use scratch ivars freely, but the instance is dropped once the return value is captured and the
scratch never leaks past its own execution.

Blocks are `(params) -> value` pure functions with explicit arguments and return values. Constants
resolve lexically and `Kernel` stays reachable.

Six sites run blocks this way, and what each is handed is the thing to check first when a block sees
the wrong picture:

| site | block | handed |
|------|-------|--------|
| `page/head.rb` | a page `title` block | the page's bag, or an empty one |
| `params.rb` | a `derives` / `defines` thunk | the bag doing the reading |
| `dsl/identity.rb` | `identifies_by` | a bag restricted to the identifying params |
| `router/companions.rb` | `brings` | the companion's view of its lineage |
| `router/actions.rb` | an action callable | the composed request state |
| `router/errors.rb` | `recovers` | the composed state, plus the error |

The companion site is the subtle one. A companion block must be handed the *companion's* view, not the
host's — the invariant is that a block and the render beneath it share one lineage. Whenever a
companion's view falls back to some default, its lineage has to fall back the same way; a block reading
one picture while its component inherits another is precisely how re-derivation creeps in.

> **Stated intention, not current structure:** these blocks are intended to receive the request
> alongside their params, supplied by the bag rather than reachable from it — with `identifies_by`
> deliberately excluded, since a DOM id that varies with request state is an unstable swap target. The
> object that would be supplied does not exist yet.

## The standing rule

**One tree of params, which branches, evolves and composes — and is never re-invented anywhere.**

Treat a re-derivation as a bug by default rather than a design option. Most of the defects this area has
produced were the same shape: a value that stopped travelling, and a component that quietly recomputed
what the request had already paid for.
