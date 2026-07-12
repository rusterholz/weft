# frozen_string_literal: true

require "weft"
require "securerandom"
require "tempfile"
require "webmock/rspec"

# Load support files
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Isolate the global Weft registry per example. Components and Pages
  # auto-register on definition (via the `inherited` hook), so without this
  # every test class accumulates in one shared registry for the whole run —
  # leaking across examples and (once collision detection walks the registry)
  # producing spurious conflicts. Swap in a fresh registry around each example
  # and restore the original afterward. The gem's own Defaults need not be
  # re-registered: recovery resolves them through Weft.configuration, not the
  # registry.
  config.around do |example|
    original_registry = Weft.instance_variable_get(:@registry)
    Weft.instance_variable_set(:@registry, Weft::Registry.new)
    example.run
    Weft.instance_variable_set(:@registry, original_registry)
  end
end
