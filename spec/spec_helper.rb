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

  # Isolate the two pieces of process-wide Weft state per example, both held as
  # memoized ivars on the Weft module: swap in a fresh one, run, put the
  # original back.
  #
  # The registry, because Components and Pages auto-register on definition (via
  # the `inherited` hook), so without this every test class accumulates in one
  # shared registry for the whole run — leaking across examples and (once
  # collision detection walks the registry) producing spurious conflicts. The
  # gem's own Defaults need not be re-registered: recovery resolves them through
  # Weft.configuration, not the registry.
  #
  # The configuration, because a knob set in one example otherwise follows the
  # rest of the run — and the failure surfaces nowhere near its cause. One
  # assignment to `error_component` cost eleven router specs that passed in
  # isolation. Class-valued knobs are the sharpest case: they memoize their
  # default on first read, so a fresh Configuration is what restores them.
  #
  # Swapping the object is half the job. Weft.configure pushes derived state
  # outward — the Router's :logging setting, the logger's level — and those
  # copies outlive the configuration they came from, so each swap is followed by
  # an apply. It is private because applications go through Weft.configure, and
  # idempotent by its own contract, which is what makes calling it here safe.
  config.around do |example|
    original_registry = Weft.instance_variable_get(:@registry)
    original_configuration = Weft.instance_variable_get(:@configuration)
    Weft.instance_variable_set(:@registry, Weft::Registry.new)
    Weft.instance_variable_set(:@configuration, Weft::Configuration.new)
    Weft.send(:apply_configuration)
    example.run
    Weft.instance_variable_set(:@registry, original_registry)
    Weft.instance_variable_set(:@configuration, original_configuration)
    Weft.send(:apply_configuration)
  end
end
