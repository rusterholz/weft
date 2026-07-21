# frozen_string_literal: true

module Weft
  module DSL
    # The `self` a verb block runs against — a "void context": empty of
    # anything component-specific, so a block cannot reach local state and is
    # portable to any process. Verb blocks (`derives`, `performs`, `transfers`,
    # `recovers`, `includes`) are `(params) -> value` pure functions: their
    # arguments and return value are explicit, constants resolve lexically, and
    # Kernel stays reachable (raise, format, Integer()).
    #
    # Each execution runs in a fresh instance, dropped once the return value is
    # captured — so a block may use scratch instance variables freely, but that
    # scratch never leaks past its own execution. Instances are deliberately
    # unfrozen (scratch is allowed) yet non-leaking (freshness, not freezing,
    # is what isolates them); a future +register_helpers+ facility would add
    # vocabulary here without changing that contract.
    class Sandbox
      # Run a block in a fresh sandbox and return its value. Extra arguments
      # after +params+ ride through to the block (recovery blocks take
      # +(params, error)+). Each call gets its own instance by construction, so
      # no caller can reuse one across executions.
      def self.run(...) = new.instance_exec(...)
    end
  end
end
