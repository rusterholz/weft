# frozen_string_literal: true

module Drills
  # A full-document render that always raises; the Weft::Page chain answers
  # with the branded error page and status 500.
  class BoomPage < ApplicationPage
    self.page_path = "/drills/boom"

    def build(_attributes = {})
      raise "the page drill exploded, as requested"
    end
  end
end
