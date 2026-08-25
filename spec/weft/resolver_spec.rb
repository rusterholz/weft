# frozen_string_literal: true

require "bigdecimal"

RSpec.describe Weft::Resolver do
  subject(:resolver) { described_class }

  let(:component_class) do
    Class.new(Weft::Component) do
      def self.name = "TestComponent"
      param :status, default: "pending", type: :string
      param :count, default: 0, type: :integer
      param :rate, default: 1.5, type: :float
      param :active, default: true, type: :boolean
      param :price, type: :decimal
      param :label
    end
  end

  describe ".resolve" do
    it "coerces wire strings into their declared types" do
      result = resolver.resolve(
        component_class,
        "status" => "shipped", "count" => "42", "rate" => "3.14",
        "active" => "false", "price" => "19.99"
      )

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(42)
      expect(result[:rate]).to eq(3.14)
      expect(result[:active]).to be(false)
      expect(result[:price]).to eq(BigDecimal("19.99"))
    end

    it "coerces :decimal with full precision, not through Float" do
      result = resolver.resolve(component_class, "price" => "0.1")

      expect(result[:price]).to be_a(BigDecimal)
      expect(result[:price]).to eq(BigDecimal("0.1"))
    end

    # Was "maps only true and 1 to true". That allowlist silently answered
    # `false` for everything it did not recognise, including the `"on"` a bare
    # HTML checkbox submits — so a checked box read as unchecked. Strict mode
    # replaces guessing with a vocabulary: what it knows, it converts; what it
    # does not know, it refuses.
    it "reads the whole boolean vocabulary, case-insensitively" do
      %w[true 1 t on yes y TRUE On YES].each do |word|
        expect(resolver.resolve(component_class, "active" => word)[:active]).to be(true), word
      end
      %w[false 0 f off no n FALSE Off NO].each do |word|
        expect(resolver.resolve(component_class, "active" => word)[:active]).to be(false), word
      end
    end

    # An empty wire value is a cleared field, a reset filter, a `?q=&page=` —
    # absence spelled in the only way a query string can spell it. Treating it
    # as a value is how `?page=` used to render page 0 with `default: 1` sitting
    # right there. ActiveModel casts blank to nil for the same reason.
    it "treats an empty numeric wire value as absent, so the default applies" do
      # Defaults deliberately non-zero: `"".to_i` is 0, so a zero default could
      # not tell the fix from the bug.
      klass = Class.new(Weft::Component) do
        def self.name = "BlankNumeric"
        param :count, default: 7, type: :integer
        param :rate, default: 1.5, type: :float
        param :price, type: :decimal
      end

      result = resolver.resolve(klass, "count" => "", "rate" => "", "price" => "")

      expect(result[:count]).to eq(7)
      expect(result[:rate]).to eq(1.5)
      expect(result[:price]).to be_nil
    end

    it "treats an empty boolean wire value as absent, so the default applies" do
      result = resolver.resolve(component_class, "active" => "")

      expect(result[:active]).to be(true)
    end

    it "keeps an empty value on an untyped param, which promises no conversion" do
      klass = Class.new(Weft::Component) do
        def self.name = "UntypedBlank"
        param :note, default: "none"
      end

      expect(resolver.resolve(klass, "note" => "")[:note]).to eq("")
    end

    it "coerces :string with to_s, so a rich pseudo-wire value becomes a string" do
      result = resolver.resolve(component_class, "status" => :shipped)

      expect(result[:status]).to eq("shipped")
    end

    it "never coerces an untyped param, even when its default looks typed" do
      klass = Class.new(Weft::Component) do
        def self.name = "UntypedTest"
        param :page, default: 1
        param :flag, default: false
      end

      result = resolver.resolve(klass, "page" => "2", "flag" => "true")

      expect(result[:page]).to eq("2")
      expect(result[:flag]).to eq("true")
    end

    it "passes rich values (Hash, Array) through untyped params unchanged" do
      klass = Class.new(Weft::Component) do
        def self.name = "RichTest"
        param :items
        param :tags
      end

      result = resolver.resolve(klass, "items" => { "widget" => "3" }, "tags" => %w[a b])

      expect(result[:items]).to eq("widget" => "3")
      expect(result[:tags]).to eq(%w[a b])
    end

    it "applies defaults for missing params without coercing them" do
      result = resolver.resolve(component_class, {})

      expect(result[:status]).to eq("pending")
      expect(result[:count]).to eq(0)
      expect(result[:rate]).to eq(1.5)
      expect(result[:active]).to be(true)
      expect(result[:price]).to be_nil
      expect(result[:label]).to be_nil
    end

    it "ignores params not declared" do
      result = resolver.resolve(component_class, "status" => "shipped", "unknown" => "ignored")

      expect(result).not_to have_key(:unknown)
      expect(result.keys).to match_array(%i[status count rate active price label])
    end

    it "accepts symbol keys as well as string keys" do
      result = resolver.resolve(component_class, status: "shipped", count: "5")

      expect(result[:status]).to eq("shipped")
      expect(result[:count]).to eq(5)
    end

    it "treats a literal false under a string key as present, not absent" do
      result = resolver.resolve(component_class, "active" => false)

      expect(result[:active]).to be(false)
    end

    it "treats a literal false under a symbol key as present, not absent" do
      result = resolver.resolve(component_class, active: false)

      expect(result[:active]).to be(false)
    end
  end

  # The Resolver never raises. It reports what it could not represent and lets
  # the caller decide — which is what lets the error path re-resolve the same
  # malformed wire hash without raising a second time on top of the first.
  describe ".resolution" do
    let(:strict_class) do
      Class.new(Weft::Component) do
        def self.name = "StrictComponent"
        param :page, default: 1, type: :integer
        param :label, type: :string
      end
    end

    it "reports a violation naming the key, what arrived, and the type it failed" do
      resolution = resolver.resolution(strict_class, { "page" => "wombat" })

      expect(resolution.violations.size).to eq(1)
      violation = resolution.violations.first
      expect(violation.key).to eq(:page)
      expect(violation.raw).to eq("wombat")
      expect(violation.type).to eq(:integer)
    end

    it "leaves a violated key out of the values, so it falls to its default" do
      resolution = resolver.resolution(strict_class, { "page" => "wombat" }, fill_defaults: true)

      expect(resolution.coerced[:page]).to eq(1)
    end

    it "keeps the keys that did coerce, so a form redraw does not lose them" do
      resolution = resolver.resolution(strict_class, { "page" => "wombat", "label" => "kept" })

      expect(resolution.coerced[:label]).to eq("kept")
    end

    it "collects every violation rather than stopping at the first" do
      klass = Class.new(Weft::Component) do
        def self.name = "TwoBad"
        param :page, type: :integer
        param :rate, type: :float
      end

      resolution = resolver.resolution(klass, { "page" => "wombat", "rate" => "badger" })

      expect(resolution.violations.map(&:key)).to eq(%i[page rate])
    end

    it "reports nothing when the param opts out of strictness" do
      klass = Class.new(Weft::Component) do
        def self.name = "LenientParam"
        param :page, type: :integer, strict: false
      end

      resolution = resolver.resolution(klass, { "page" => "wombat" })

      expect(resolution.violations).to be_empty
      expect(resolution.coerced[:page]).to eq(0)
    end

    it "reports nothing when the gem-wide default is off and the param says nothing" do
      Weft.configuration.strict_params = false

      resolution = resolver.resolution(strict_class, { "page" => "wombat" })

      expect(resolution.violations).to be_empty
    end

    it "still reports when the param overrides a gem-wide default of off" do
      Weft.configuration.strict_params = false
      klass = Class.new(Weft::Component) do
        def self.name = "StrictParam"
        param :page, type: :integer, strict: true
      end

      expect(resolver.resolution(klass, { "page" => "wombat" }).violations.size).to eq(1)
    end

    it "treats an untyped param as unconstrained, whatever arrives" do
      klass = Class.new(Weft::Component) do
        def self.name = "UntypedStrict"
        param :anything
      end

      expect(resolver.resolution(klass, { "anything" => "wombat" }).violations).to be_empty
    end

    describe "what each type will and will not represent" do
      def violations_for(type, value)
        klass = Class.new(Weft::Component) do
          def self.name = "TypedProbe"
          param :probe, type: type
        end
        resolver.resolution(klass, { "probe" => value }).violations
      end

      it "refuses a numeric string that to_i or to_f would silently truncate" do
        expect(violations_for(:integer, "1.5")).not_to be_empty
        expect(violations_for(:integer, "12abc")).not_to be_empty
        expect(violations_for(:integer, "42")).to be_empty
        expect(violations_for(:integer, "-7")).to be_empty
      end

      # Kernel#Integer reads these; the to_i that actually coerces does not.
      # Blessing them would let strict pass a value that renders as 0.
      it "refuses hex and other Kernel#Integer forms the coercion cannot read" do
        expect(violations_for(:integer, "0x1f")).not_to be_empty
      end

      it "accepts the decimal and exponent forms to_f and to_d read faithfully" do
        expect(violations_for(:float, "3.14")).to be_empty
        expect(violations_for(:float, "1e5")).to be_empty
        expect(violations_for(:decimal, "19.99")).to be_empty
        expect(violations_for(:decimal, "wombat")).not_to be_empty
      end

      it "refuses a boolean word it has no meaning for" do
        expect(violations_for(:boolean, "wombat")).not_to be_empty
        expect(violations_for(:boolean, "yes")).to be_empty
      end

      # `?probe[]=a&probe[]=b` and `?probe[k]=v` are attacker-controlled
      # SHAPES, not just values. Filtering stops undeclared keys; it does not
      # stop a declared key arriving as a collection, and `to_s` would render
      # `["a", "b"]` straight into the page.
      it "refuses a collection where a scalar was declared" do
        expect(violations_for(:string, %w[a b])).not_to be_empty
        expect(violations_for(:string, { "k" => "v" })).not_to be_empty
        expect(violations_for(:string, "plain")).to be_empty
      end

      it "refuses a uuid-typed value that is not a uuid, in either case" do
        expect(violations_for(:uuid, "wombat")).not_to be_empty
        expect(violations_for(:uuid, "01c65910-3a20-4d7b-9f31-8e2c5a94b6d0")).to be_empty
        expect(violations_for(:uuid, "01C65910-3A20-4D7B-9F31-8E2C5A94B6D0")).to be_empty
      end

      it "treats blank as absence rather than malformation, for every type" do
        %i[integer float decimal boolean uuid].each do |type|
          expect(violations_for(type, "")).to be_empty, type.to_s
        end
      end
    end
  end

  describe ".resolve_present" do
    it "coerces only the keys on the wire, without default fill" do
      result = resolver.resolve_present(component_class, "count" => "7")

      expect(result).to eq(count: 7)
    end

    it "treats a literal false under a string key as present" do
      result = resolver.resolve_present(component_class, "active" => false)

      expect(result).to eq(active: false)
    end
  end
end
