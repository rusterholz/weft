# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::DSL::Recoveries do
  describe "recovers DSL" do
    # The gem-default `recovers from: StandardError, with: :error_component` on
    # Weft::Component is inherited by every subclass. Tests in this block assert
    # against subclass-own entries (the first N of recoveries), with the gem
    # default trailing as inherited.
    it "stores a single entry with from:, with: nil, and the block" do
      handler = ->(_params, _error) { { message: "oops" } }
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable, &handler)

      expect(component_class.recoveries.first).to eq(
        from: Weft::Unprocessable, with: nil, status: nil, block: handler
      )
    end

    it "stores an entry with an explicit with: target" do
      target = Class.new(Weft::Component) do
        def self.name = "ErrorTarget"
      end
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable, with: target)

      expect(component_class.recoveries.first).to eq(
        from: Weft::Unprocessable, with: target, status: nil, block: nil
      )
    end

    it "stores a declared status: override" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: KeyError, with: :error_component, status: 404)

      expect(component_class.recoveries.first[:status]).to eq(404)
    end

    it "raises InvalidUsage for a status: outside the HTTP error range" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end

      expect { component_class.recovers(from: KeyError, status: 200) }.
        to raise_error(Weft::InvalidUsage, /status/)
    end

    it "raises InvalidUsage for a non-integer status:" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end

      expect { component_class.recovers(from: KeyError, status: "404") }.
        to raise_error(Weft::InvalidUsage, /status/)
    end

    it "accepts a Symbol with: for configuration-time resolution" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: StandardError, with: :error_component)

      expect(component_class.recoveries.first[:with]).to eq(:error_component)
    end

    it "accumulates multiple recovers calls as separate entries in declaration order" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end
      component_class.recovers(from: Weft::Unprocessable)
      component_class.recovers(from: Weft::Unauthorized)

      from_values = component_class.recoveries.map { |e| e[:from] }.take(2)
      expect(from_values).to eq([Weft::Unprocessable, Weft::Unauthorized])
    end

    it "raises ArgumentError when from: is missing" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Recoverable"
      end

      expect { component_class.recovers }.to raise_error(ArgumentError, /:from/)
    end

    it "inherits recovers entries from parent class" do
      parent = Class.new(Weft::Component) do
        def self.name = "ParentRecover"
      end
      parent.recovers(from: Weft::Unprocessable)
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end

      from_values = child.recoveries.map { |e| e[:from] }
      expect(from_values).to start_with(Weft::Unprocessable)
    end

    it "child entries precede parent entries in the chain (most-specific first)" do
      parent = Class.new(Weft::Component) do
        def self.name = "ParentRecover"
      end
      parent.recovers(from: Weft::Unprocessable)
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end
      child.recovers(from: Weft::Unauthorized)

      from_values = child.recoveries.map { |e| e[:from] }.take(2)
      expect(from_values).to eq([Weft::Unauthorized, Weft::Unprocessable])
    end

    it "child entries do not leak into the parent class" do
      parent = Class.new(Weft::Component) do
        def self.name = "ParentRecover"
      end
      child = Class.new(parent) do
        def self.name = "ChildRecover"
      end
      child.recovers(from: Weft::Unprocessable)

      expect(parent.recoveries.map { |e| e[:from] }).not_to include(Weft::Unprocessable)
    end

    it "every Weft::Component subclass inherits a gem-default StandardError entry targeting :error_component" do
      component_class = Class.new(Weft::Component) do
        def self.name = "PlainComponent"
      end

      gem_default = component_class.recoveries.last
      expect(gem_default).to eq(from: StandardError, with: :error_component, status: nil, block: nil)
    end

    it "inherits a gem-default Weft::NotFound entry targeting :not_found_component, ahead of the StandardError entry" do
      component_class = Class.new(Weft::Component) do
        def self.name = "PlainNotFoundComponent"
      end

      entries = component_class.recoveries
      not_found_entry = entries.find { |e| e[:from] == Weft::NotFound }
      expect(not_found_entry).to eq(from: Weft::NotFound, with: :not_found_component, status: nil, block: nil)
      # Ordered before the StandardError gem-default so a component-context
      # NotFound resolves to the 404 body, not the generic error component.
      expect(entries.index(not_found_entry)).to be < entries.index(entries.last)
      expect(entries.last).to eq(from: StandardError, with: :error_component, status: nil, block: nil)
    end
  end

  describe ".recovery_for" do
    it "returns the gem-default StandardError entry when no user entry matches" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NoRecover"
      end
      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:with]).to eq(:error_component)
    end

    it "resolves a component-context Weft::NotFound to the :not_found_component gem-default" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NotFoundResolver"
      end
      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:not_found_component)
    end

    it "returns nil for an exception outside StandardError's hierarchy" do
      component_class = Class.new(Weft::Component) do
        def self.name = "NoRecover"
      end
      expect(component_class.recovery_for(Exception.new)).to be_nil
    end

    it "matches by Class (subclass-inclusive)" do
      component_class = Class.new(Weft::Component) do
        def self.name = "ClassMatcher"
      end
      component_class.recovers(from: Weft::HTTPError)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(Weft::HTTPError)
    end

    it "matches a foreign exception class directly" do
      foreign_error = Class.new(StandardError)
      component_class = Class.new(Weft::Component) do
        def self.name = "ForeignMatcher"
      end
      component_class.recovers(from: foreign_error)

      entry = component_class.recovery_for(foreign_error.new)
      expect(entry[:from]).to eq(foreign_error)
    end

    it "matches by Integer status on HTTPError" do
      component_class = Class.new(Weft::Component) do
        def self.name = "IntMatcher"
      end
      component_class.recovers(from: 404)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(404)
    end

    it "treats a non-HTTPError exception as status 500" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Int500Matcher"
      end
      component_class.recovers(from: 500)

      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(500)
    end

    it "does not match a non-HTTPError exception against an unrelated Integer status" do
      component_class = Class.new(Weft::Component) do
        def self.name = "IntMissMatcher"
      end
      component_class.recovers(from: 404)

      # The own Integer-status entry doesn't match StandardError, but the gem-default
      # StandardError entry is still in the chain — so .recovery_for falls through to it.
      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(StandardError)
    end

    it "matches by Range over HTTPError status" do
      component_class = Class.new(Weft::Component) do
        def self.name = "RangeMatcher"
      end
      component_class.recovers(from: 400..499)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:from]).to eq(400..499)
    end

    it "treats non-HTTPError exceptions as status 500 for Range matching" do
      component_class = Class.new(Weft::Component) do
        def self.name = "Range500Matcher"
      end
      component_class.recovers(from: 500..599)

      entry = component_class.recovery_for(StandardError.new)
      expect(entry[:from]).to eq(500..599)
    end

    it "matches by Array (any element matches)" do
      foreign_error = Class.new(StandardError)
      component_class = Class.new(Weft::Component) do
        def self.name = "ArrayMatcher"
      end
      component_class.recovers(from: [Weft::Forbidden, foreign_error])

      expect(component_class.recovery_for(foreign_error.new)[:from]).to eq(
        [Weft::Forbidden, foreign_error]
      )
      expect(component_class.recovery_for(Weft::Forbidden.new)[:from]).to eq(
        [Weft::Forbidden, foreign_error]
      )
    end

    it "returns first matching entry in chain order" do
      component_class = Class.new(Weft::Component) do
        def self.name = "FirstWins"
      end
      component_class.recovers(from: Weft::HTTPError, with: :first)
      component_class.recovers(from: Weft::NotFound, with: :second)

      entry = component_class.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:first)
    end

    it "subclass entries take precedence over ancestor entries" do
      parent = Class.new(Weft::Component) do
        def self.name = "ParentRecover2"
      end
      parent.recovers(from: StandardError, with: :parent_target)
      child = Class.new(parent) do
        def self.name = "ChildRecover2"
      end
      child.recovers(from: Weft::NotFound, with: :child_target)

      entry = child.recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(:child_target)
    end
  end

  describe ".component_recovery_for" do
    it "returns the first matching entry when its target is a component" do
      recovery_target = Class.new(Weft::Component) { def self.name = "FallbackCard" }
      component_class = Class.new(Weft::Component) do
        def self.name = "ComponentTargeted"
      end
      component_class.recovers(from: StandardError, with: recovery_target)

      entry = component_class.component_recovery_for(StandardError.new)
      expect(entry[:with]).to eq(recovery_target)
    end

    it "treats a with:-less entry (self target) as a component target" do
      component_class = Class.new(Weft::Component) do
        def self.name = "SelfRecovering"
      end
      component_class.recovers(from: StandardError)

      entry = component_class.component_recovery_for(StandardError.new)
      expect(entry[:with]).to be_nil
    end

    it "skips a matching Page-target entry and falls through to the gem default" do
      error_page = Class.new(Weft::Page) { def self.name = "StreamErrorPage" }
      component_class = Class.new(Weft::Component) do
        def self.name = "PageTargeted"
      end
      component_class.recovers(from: StandardError, with: error_page)

      entry = component_class.component_recovery_for(StandardError.new)
      expect(entry[:with]).to eq(:error_component)
    end

    it "skips a matching Page-target entry in favor of a later component-target match" do
      login_page = Class.new(Weft::Page) { def self.name = "StreamLoginPage" }
      notice_card = Class.new(Weft::Component) { def self.name = "NoticeCard" }
      component_class = Class.new(Weft::Component) do
        def self.name = "MixedTargets"
      end
      component_class.recovers(from: Weft::HTTPError, with: login_page)
      component_class.recovers(from: Weft::NotFound, with: notice_card)

      entry = component_class.component_recovery_for(Weft::NotFound.new)
      expect(entry[:with]).to eq(notice_card)
    end

    it "resolves Symbol targets during the walk, skipping those that name Pages" do
      component_class = Class.new(Weft::Component) do
        def self.name = "SymbolPageTargeted"
      end
      component_class.recovers(from: StandardError, with: :error_page)

      entry = component_class.component_recovery_for(StandardError.new)
      expect(entry[:with]).to eq(:error_component)
    end
  end

  describe ".resolve_recovery_target" do
    it "returns the with: class directly when it is a Class" do
      target = Class.new
      component_class = Class.new(Weft::Component) do
        def self.name = "ResolverComp"
      end
      entry = { from: StandardError, with: target, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(target)
    end

    it "resolves a Symbol with: through Weft.configuration" do
      component_class = Class.new(Weft::Component) do
        def self.name = "ResolverComp"
      end
      fake_page = Class.new
      allow(Weft.configuration).to receive(:not_found_page).and_return(fake_page)
      entry = { from: StandardError, with: :not_found_page, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(fake_page)
    end

    it "falls back to self when with: is nil" do
      component_class = Class.new(Weft::Component) do
        def self.name = "ResolverComp"
      end
      entry = { from: StandardError, with: nil, block: nil }

      expect(component_class.resolve_recovery_target(entry)).to eq(component_class)
    end
  end
end
