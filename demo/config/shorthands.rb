# frozen_string_literal: true

# Demo-defined Weft shorthand: :paginate
#
# Shape: `button label, paginate: TargetComponentClass, with: { ... },
#                       target: "#selector", push_url: "/path"`
#
# Defaults to click trigger and replace swap — semantically "click this
# to load TargetComponentClass into the target selector, replacing the
# current node entirely." Identical to `loads:` machinery, just named
# for the pagination use case so the call site reads as intent.
#
# Registered here (not in the gem) to showcase how a user-facing app
# can add its own shorthands. Same API the gem uses internally for the
# v0.1 shipped presets (tooltip, inline_expand, etc.).
Weft::Shorthands.register :paginate, trigger: :click, swap: :replace
