# frozen_string_literal: true

require "weft/context"
require "weft/request/event_frame"

# Builds a Weft::Context in a frame of its own over +wire+, as one delivery,
# which is what most specs rendering a tree by hand need.
module WeftContextHelper
  def weft_context(wire = {}, **, &)
    Weft::Context.new(frame: Weft::Request::EventFrame.new(wire || {}, request: Weft::Request.wrap(nil)), **, &)
  end
end

RSpec.configure { |config| config.include WeftContextHelper }
