# frozen_string_literal: true

# What spec_helper guarantees each example starts from. These read as trivia
# until an example leaks: a knob set here and read three files later fails
# something that has nothing to do with configuration, and the hunt starts in
# the wrong place. Pinning the guarantee keeps the harness honest about itself.
#
# Examples run in defined order (no --order random), so each "mutates" example
# reliably precedes the one asserting a pristine start.
RSpec.describe "spec-harness isolation of process-wide state" do
  describe "the configuration" do
    it "lets an example mutate a plain knob" do
      Weft.configuration.verbose_error_pages = false

      expect(Weft.configuration.verbose_error_pages).to be(false)
    end

    it "hands the next example a pristine plain knob" do
      expect(Weft.configuration.verbose_error_pages).to be(true)
    end

    # The knob that actually leaked in M3.5: assigning it made eleven router
    # specs fail in a run where each passed in isolation.
    it "lets an example mutate a class-valued knob" do
      stub_const("LeakyErrorComponent", Class.new(Weft::Component))
      Weft.configuration.error_component = LeakyErrorComponent

      expect(Weft.configuration.error_component).to be(LeakyErrorComponent)
    end

    it "hands the next example a pristine class-valued knob" do
      expect(Weft.configuration.error_component).to be(Weft::Defaults::ErrorComponent)
    end

    # Swapping the configuration object is only half the job: Weft.configure
    # pushes derived state outward, onto the Router and the logger, and those
    # copies outlive the object they came from.
    it "lets an example apply a knob that lands outside the configuration" do
      Weft.configure { |c| c.router_logging = true }

      expect(Weft::Router.settings.logging).to be(true)
    end

    it "hands the next example pristine derived state" do
      expect(Weft::Router.settings.logging).to be(false)
      expect(Weft.logger.level).to eq(Logger::INFO)
    end
  end

  describe "the registry" do
    it "lets an example register a component" do
      stub_const("TransientCard", Class.new(Weft::Component))

      expect(Weft.registry.components).to include(TransientCard)
    end

    it "hands the next example a registry without it" do
      expect(Weft.registry.components.map(&:name)).not_to include("TransientCard")
    end
  end
end
