# frozen_string_literal: true

require "weft/context"
require "weft/params/assembly"
require "weft/request"
require "weft/request/event_frame"

# Builds a Weft::Context in a frame of its own over +wire+, as one delivery,
# which is what most specs rendering a tree by hand need. A +branch_bag+
# carries its own universe, so it comes with no separate wire.
module WeftContextHelper
  def weft_context(wire = {}, branch_bag: nil, **, &)
    raise ArgumentError, "a branch_bag carries its own universe; build it over the wire" if branch_bag && wire&.any?

    frame = Weft::Request::EventFrame.new(Weft::Request.wrap(nil))
    Weft::Context.new(frame: frame, branch_bag: branch_bag || Weft::Params::Assembly.empty(wire || {}), **, &)
  end
end

RSpec.configure { |config| config.include WeftContextHelper }
