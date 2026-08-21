# frozen_string_literal: true

# Weft's bag discipline, in executable form. A params bag is REUSED where one
# exists, DERIVED from one where a variation is needed (branch_bag:/overlay),
# ASSEMBLED only where none exists yet, and never hand-built. These guard the
# two shapes that break it, and fail with the rule rather than with a diff.
RSpec.describe Weft::Params do
  describe "bag discipline across lib/" do
    def lib_lines
      Dir[File.expand_path("../../lib/**/*.rb", __dir__)].flat_map do |path|
        rel = path.sub(%r{\A.*/lib/}, "")
        File.readlines(path).each_with_index.map { |line, i| [rel, i + 1, line] }
      end
    end

    it "hand-builds a bag only to stand for the absence of one" do
      # Params.new with real data yields no thunks, no defaults and no
      # provenance — a hash wearing a bag's interface, which a verb block
      # cannot read what it needs from. Assembly builds the real thing;
      # elsewhere `Params.new({})` says "there was no bag here".
      offenders = lib_lines.select do |file, _line, text|
        file != "weft/params/assembly.rb" &&
          text.match?(/Params\.new\(/) && !text.match?(/Params\.new\(\{\}\)/)
      end

      expect(offenders).to be_empty, lambda {
        listed = offenders.map { |f, l, t| "  #{f}:#{l}  #{t.strip}" }.join("\n")
        "Hand-built a params bag with data in it:\n#{listed}\n\n" \
          "Reuse the bag in scope, branch it (branch_bag:) or overlay it. If none " \
          "exists, assemble one — do not construct a partial bag."
      }
    end

    it "assembles a bag only where the request has none yet" do
      # Every permitted site is a genuine entry point: the top of a render, an
      # action, a stream frame, a component's own construction, a companion's
      # own schema, or the public class-level entry that must accept a hash.
      permitted = %w[
        weft/dsl/identity.rb weft/dsl/params.rb weft/page/head.rb weft/router.rb
        weft/router/actions.rb weft/router/companions.rb weft/router/streaming.rb
      ]
      sites = lib_lines.select { |_f, _l, t| t.match?(/Assembly\.(for_request|call)\(/) }.
              map(&:first).uniq

      expect(sites - permitted).to be_empty, lambda {
        "A new params bag is assembled in #{(sites - permitted).join(', ')}. Before adding a " \
          "site, check whether the request already composed one: a second bag beside an " \
          "existing one re-runs every derivation the first has already forced."
      }
    end
  end
end
