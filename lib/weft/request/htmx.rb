# frozen_string_literal: true

module Weft
  class Request
    # The headers htmx sends with each request it makes, read by name. Every
    # reader answers nil (or false) on a request htmx did not send.
    class Htmx
      def initialize(request)
        @request = request
      end

      # The id of the element being swapped into, when it has one.
      def target = @request.header("HX-Target")

      # The id of the element that triggered the request, when it has one.
      def trigger = @request.header("HX-Trigger")

      # The name attribute of the element that triggered the request.
      def trigger_name = @request.header("HX-Trigger-Name")

      # The browser's URL when the request was made.
      def current_url = @request.header("HX-Current-URL")

      # What the user typed into an `hx-prompt` dialog.
      def prompt = @request.header("HX-Prompt")

      def boosted? = @request.header("HX-Boosted") == "true"

      # True when htmx is restoring a page its history cache missed.
      def history_restore? = @request.header("HX-History-Restore-Request") == "true"
    end
  end
end
