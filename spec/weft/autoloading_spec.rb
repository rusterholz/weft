# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Weft::Autoloading do
  let(:app_dir) { Dir.mktmpdir("weft-autoloading") }

  # The reload hook reads Weft.configuration; isolate the global instance.
  around do |example|
    original = Weft.instance_variable_get(:@configuration)
    Weft.instance_variable_set(:@configuration, Weft::Configuration.new)
    example.run
    Weft.instance_variable_set(:@configuration, original)
  end

  after do
    described_class.loaders.each(&:unload)
    described_class.loaders.clear
    FileUtils.remove_entry(app_dir)
  end

  def write_class(const_name, file_name, body: "param :x")
    File.write(File.join(app_dir, "#{file_name}.rb"), <<~RUBY)
      class #{const_name} < Weft::Component
        #{body}
      end
    RUBY
  end

  describe "Weft.configure_autoloading" do
    it "eager-loads the configured paths so components register and route" do
      write_class("ZwAlphaCard", "zw_alpha_card")

      Weft.configure_autoloading(paths: [app_dir])

      expect(Weft.registry.lookup("/_components/zw_alpha_card")).to eq(Object.const_get(:ZwAlphaCard))
    end

    it "returns the loader and tracks it" do
      write_class("ZwBetaCard", "zw_beta_card")

      loader = Weft.configure_autoloading(paths: [app_dir])

      expect(loader).to be_a(Zeitwerk::Loader)
      expect(described_class.loaders).to include(loader)
    end

    it "applies inflections" do
      write_class("ZwUICard", "zw_ui_card")

      Weft.configure_autoloading(paths: [app_dir], inflections: { "zw_ui_card" => "ZwUICard" })

      expect(Weft.registry.lookup("/_components/zw_ui_card")).to eq(Object.const_get(:ZwUICard))
    end

    it "accepts a single path without array wrapping" do
      write_class("ZwSoloCard", "zw_solo_card")

      Weft.configure_autoloading(paths: app_dir)

      expect(Weft.registry.lookup("/_components/zw_solo_card")).to eq(Object.const_get(:ZwSoloCard))
    end

    it "raises Weft::InvalidConfiguration when paths is empty" do
      expect { Weft.configure_autoloading(paths: []) }.
        to raise_error(Weft::InvalidConfiguration, /at least one/)
    end

    it "raises Weft::InvalidConfiguration on non-string inflections" do
      expect { Weft.configure_autoloading(paths: [app_dir], inflections: { zw: :bad }) }.
        to raise_error(Weft::InvalidConfiguration, /inflections/)
    end

    it "does not enable reloading or install a request hook by default" do
      write_class("ZwGammaCard", "zw_gamma_card")
      allow(Weft::Router).to receive(:before)

      loader = Weft.configure_autoloading(paths: [app_dir])

      expect(loader.reloading_enabled?).to be(false)
      expect(Weft::Router).not_to have_received(:before)
    end
  end

  describe "reload: true" do
    let(:hooks) { [] }

    before do
      allow(Weft::Router).to receive(:before) { |*_args, &blk| hooks << blk }
    end

    # Simulate a dev-mode request landing: run the installed before-hook.
    def tick = hooks.each(&:call)

    it "enables reloading and installs the per-request hook" do
      write_class("ZwDeltaCard", "zw_delta_card")

      loader = Weft.configure_autoloading(paths: [app_dir], reload: true)

      expect(loader.reloading_enabled?).to be(true)
      expect(hooks.size).to eq(1)
    end

    it "serves the fresh class after a reload, evicting the superseded one" do
      write_class("ZwReloadCard", "zw_reload_card")
      Weft.configure_autoloading(paths: [app_dir], reload: true)
      original = Object.const_get(:ZwReloadCard)

      write_class("ZwReloadCard", "zw_reload_card", body: "param :x\n  param :y")
      tick

      current = Object.const_get(:ZwReloadCard)
      expect(current).not_to equal(original)
      expect { Weft.registry.lookup("/_components/zw_reload_card") }.not_to raise_error
      expect(Weft.registry.lookup("/_components/zw_reload_card")).to eq(current)
      expect(Weft.registry.components).not_to include(original)
    end

    it "evicts a deleted class so its route is gone (no zombie)" do
      write_class("ZwDoomedCard", "zw_doomed_card")
      write_class("ZwSurvivorCard", "zw_survivor_card")
      Weft.configure_autoloading(paths: [app_dir], reload: true)
      expect(Weft.registry.lookup("/_components/zw_doomed_card")).not_to be_nil

      FileUtils.rm(File.join(app_dir, "zw_doomed_card.rb"))
      tick

      expect(Weft.registry.lookup("/_components/zw_doomed_card")).to be_nil
      expect(Weft.registry.lookup("/_components/zw_survivor_card")).not_to be_nil
    end

    it "does not reload when no file has changed" do
      write_class("ZwQuietCard", "zw_quiet_card")
      Weft.configure_autoloading(paths: [app_dir], reload: true)
      original = Object.const_get(:ZwQuietCard)

      3.times { tick }

      # An unconditional reload would hand back a fresh class object each time,
      # discarding every constant in the app to rediscover the same code.
      expect(Object.const_get(:ZwQuietCard)).to equal(original)
    end

    it "reloads once when concurrent requests arrive after a single change" do
      write_class("ZwRaceCard", "zw_race_card")
      loader = Weft.configure_autoloading(paths: [app_dir], reload: true)
      counter = Mutex.new
      reloads = 0
      allow(loader).to receive(:reload).and_wrap_original do |original_method, *args|
        counter.synchronize { reloads += 1 }
        original_method.call(*args)
      end

      write_class("ZwRaceCard", "zw_race_card", body: "param :x\n  param :y")
      Array.new(4) { Thread.new { tick } }.each(&:join)

      # Zeitwerk's reload is not thread-safe: unsynchronized, every thread
      # unloads the world while its siblings are mid-render, which is how a
      # constant vanishes out from under a request that never touched a file.
      expect(reloads).to eq(1)
    end

    it "refreshes stale class knobs after the reload" do
      write_class("ZwKnobCard", "zw_knob_card")
      Weft.configure_autoloading(paths: [app_dir], reload: true)
      Weft.configuration.error_component = Object.const_get(:ZwKnobCard)
      original = Object.const_get(:ZwKnobCard)

      write_class("ZwKnobCard", "zw_knob_card", body: "param :x\n  param :z")
      tick

      expect(Weft.configuration.error_component).not_to equal(original)
      expect(Weft.configuration.error_component).to equal(Object.const_get(:ZwKnobCard))
    end
  end
end
