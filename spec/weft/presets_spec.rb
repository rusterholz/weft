# frozen_string_literal: true

RSpec.describe Weft::Presets do
  describe ".register and .lookup" do
    after { described_class.send(:registry).delete(:test_spec_preset) }

    it "registers and looks up a preset by name" do
      described_class.register :test_spec_preset, trigger: :click, swap: :fill

      result = described_class.lookup(:test_spec_preset)
      expect(result).to eq(trigger: :click, swap: :fill)
    end

    it "returns nil for unregistered names" do
      expect(described_class.lookup(:nonexistent)).to be_nil
    end
  end

  describe ".registered" do
    it "includes all shipped presets" do
      expect(described_class.registered).to include(
        :tooltip, :inline_expand, :lazy, :modal,
        :load_more, :infinite_scroll, :live_search, :tabs, :retry, :reopen_stream
      )
    end
  end

  describe "shipped presets" do
    it "tooltip has hover trigger and fill swap" do
      preset = described_class.lookup(:tooltip)
      expect(preset).to eq(trigger: :hover, swap: :fill)
    end

    it "inline_expand has click trigger and after swap" do
      preset = described_class.lookup(:inline_expand)
      expect(preset).to eq(trigger: :click, swap: :after)
    end

    it "lazy has visible trigger, fill swap, and self target" do
      preset = described_class.lookup(:lazy)
      expect(preset).to eq(trigger: :visible, swap: :fill, target: :self)
    end

    it "modal has click trigger and fill swap" do
      preset = described_class.lookup(:modal)
      expect(preset).to eq(trigger: :click, swap: :fill)
    end

    it "load_more has click trigger, replace swap, and self target" do
      preset = described_class.lookup(:load_more)
      expect(preset).to eq(trigger: :click, swap: :replace, target: :self)
    end

    it "infinite_scroll has visible trigger and after swap" do
      preset = described_class.lookup(:infinite_scroll)
      expect(preset).to eq(trigger: :visible, swap: :after)
    end

    it "live_search has input trigger and fill swap" do
      preset = described_class.lookup(:live_search)
      expect(preset).to eq(trigger: :input, swap: :fill)
    end

    it "tabs has click trigger and fill swap" do
      preset = described_class.lookup(:tabs)
      expect(preset).to eq(trigger: :click, swap: :fill)
    end

    it "retry has click trigger, outerHTML swap, and error-box target" do
      preset = described_class.lookup(:retry)
      expect(preset).to eq(trigger: :click, swap: :outer_html, target: "closest .weft-error")
    end

    it "reopen_stream has click trigger, outerHTML swap, and persistent-wrapper target" do
      preset = described_class.lookup(:reopen_stream)
      expect(preset).to eq(trigger: :click, swap: :outer_html, target: "closest [sse-swap]")
    end
  end

  describe "Weft.register_preset delegation" do
    after { described_class.send(:registry).delete(:delegated_test) }

    it "delegates to Weft::Presets.register" do
      Weft.register_preset :delegated_test, trigger: :hover, swap: :fill

      expect(described_class.lookup(:delegated_test)).to eq(trigger: :hover, swap: :fill)
    end
  end

  describe "registration name guards" do
    it "raises on a name that is Weft's own element-kwarg vocabulary" do
      expect { described_class.register :swap, trigger: :click, swap: :fill }.
        to raise_error(Weft::InvalidDefinition, /swap/)
    end

    it "reserves :prompt ahead of its arrival" do
      expect { described_class.register :prompt, trigger: :click, swap: :fill }.
        to raise_error(Weft::InvalidDefinition, /prompt/)
    end

    it "warns on a name that shadows an HTML attribute" do
      allow(Weft.logger).to receive(:warn)
      described_class.register :title, trigger: :hover, swap: :fill

      expect(Weft.logger).to have_received(:warn).with(/title/)
    ensure
      described_class.send(:registry).delete(:title)
    end

    it "registers HTML-shadowing names despite the warning" do
      allow(Weft.logger).to receive(:warn)
      described_class.register :title, trigger: :hover, swap: :fill

      expect(described_class.lookup(:title)).to eq(trigger: :hover, swap: :fill)
    ensure
      described_class.send(:registry).delete(:title)
    end

    it "neither warns nor raises on ordinary names" do
      allow(Weft.logger).to receive(:warn)
      described_class.register :test_ordinary, trigger: :click, swap: :fill

      expect(Weft.logger).not_to have_received(:warn)
    ensure
      described_class.send(:registry).delete(:test_ordinary)
    end
  end

  describe "Weft.preset delegation" do
    it "delegates to Weft::Presets.lookup" do
      expect(Weft.preset(:tooltip)).to eq(trigger: :hover, swap: :fill)
    end

    it "returns nil for unregistered names" do
      expect(Weft.preset(:nonexistent)).to be_nil
    end
  end
end
