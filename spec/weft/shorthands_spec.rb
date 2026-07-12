# frozen_string_literal: true

RSpec.describe Weft::Shorthands do
  describe ".register and .lookup" do
    after { described_class.send(:registry).delete(:test_spec_shorthand) }

    it "registers and looks up a shorthand by name" do
      described_class.register :test_spec_shorthand, trigger: :click, swap: :fill

      result = described_class.lookup(:test_spec_shorthand)
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
        :load_more, :infinite_scroll, :live_search, :tabs, :retry
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
  end

  describe "Weft.register_shorthand delegation" do
    after { described_class.send(:registry).delete(:delegated_test) }

    it "delegates to Weft::Shorthands.register" do
      Weft.register_shorthand :delegated_test, trigger: :hover, swap: :fill

      expect(described_class.lookup(:delegated_test)).to eq(trigger: :hover, swap: :fill)
    end
  end

  describe "Weft.shorthand delegation" do
    it "delegates to Weft::Shorthands.lookup" do
      expect(Weft.shorthand(:tooltip)).to eq(trigger: :hover, swap: :fill)
    end

    it "returns nil for unregistered names" do
      expect(Weft.shorthand(:nonexistent)).to be_nil
    end
  end
end
