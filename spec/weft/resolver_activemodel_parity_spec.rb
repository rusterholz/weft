# frozen_string_literal: true

require "active_model"

# Weft's lenient mode makes a promise a reader can hold in one sentence:
# turning strictness off puts you in ActiveModel::Type's semantics, exactly.
# That promise is only worth making if something checks it, and checking it
# against a table copied out of Rails would only pin what we believed on the
# day we copied it. So this compares against the real ActiveModel, which the
# Gemfile carries for test purposes only — weft's runtime pulls in nothing.
#
# When Rails changes a casting rule, this goes red and the change becomes a
# decision instead of a surprise.
#
# ⚑ The promise covers the types ActiveModel defines. `:uuid` is weft's own,
# with no ActiveModel counterpart, so it defines its own lenient behavior —
# as any registered type would.
pairings = {
  integer: ActiveModel::Type::Integer,
  float: ActiveModel::Type::Float,
  decimal: ActiveModel::Type::Decimal,
  boolean: ActiveModel::Type::Boolean,
  string: ActiveModel::Type::String
}.freeze

# Wire-shaped inputs: what a query string, a form body, or a checkbox can
# actually deliver. Includes every case where the two schemes are known to
# disagree with each other (blank handling, "no", casing, hex), because those
# are exactly the ones a remembered table gets wrong.
inputs = ["", " ", "\t", "0", "1", "42", "-7", "1.5", "1e5", "0x1f", "wombat",
          "true", "false", "True", "FALSE", "t", "f", "T", "F",
          "on", "off", "On", "OFF", "yes", "no", "y", "n", "Off", "False"].freeze

RSpec.describe Weft::Resolver do
  pairings.each do |weft_type, active_model_type|
    describe ":#{weft_type}" do
      let(:klass) do
        type = weft_type
        Class.new(Weft::Component) do
          def self.name = "ParityProbe"
          param :probe, type: type, strict: false
        end
      end

      inputs.each do |input|
        it "agrees with ActiveModel for #{input.inspect}" do
          weft_value = described_class.resolution(klass, { "probe" => input }).coerced[:probe]

          expect(weft_value).to eq(active_model_type.new.cast(input))
        end
      end
    end
  end
end
