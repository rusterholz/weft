# frozen_string_literal: true

require "weft/context"
require "weft/request/event_frame"

# Builds a Weft::Context in a frame over +wire+, as a single-root delivery
# with nothing to arbitrate, which is what most specs rendering a tree by hand need.
module WeftContextHelper
  def weft_context(wire = {}, **, &)
    Weft::Context.new(frame: Weft::Request::EventFrame.new(wire || {}), **, &)
  end
end

RSpec.configure { |config| config.include WeftContextHelper }
