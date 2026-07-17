# frozen_string_literal: true

module Weft
  # Abstract base — never raise directly; use a semantic subclass.
  # Exists for `rescue Weft::Error` to catch the whole gem-error family.
  Error = Class.new(StandardError)

  # Intermediate carrying an HTTP status. Subclass for status-bearing semantics.
  # `recovers from: Weft::HTTPError` catches the whole status-bearing family.
  class HTTPError < Error
    def self.status
      nil
    end

    def status
      self.class.status
    end
  end

  class NotFound < HTTPError
    def self.status = 404
  end

  class Unauthorized < HTTPError
    def self.status = 401
  end

  class Forbidden < HTTPError
    def self.status = 403
  end

  class Unprocessable < HTTPError
    def self.status = 422
  end

  class InternalError < HTTPError
    def self.status = 500
  end

  # Below this comment, maintain semantically-named errors (not ending in "Error") in alphabetical order, e.g.:
  #
  # OrderAlreadyFulfilled = Class.new(Error)
  # InsufficientFunds = Class.new(Error)

  # Raised for semantic mistakes inside `Weft.configure { |c| ... }` — values
  # of the right kind that nonetheless violate a constraint (e.g. an asset
  # root not starting with `/`), or state conflicts (duplicate asset bundles).
  InvalidConfiguration = Class.new(Error)

  # Raised for semantic mistakes in class-body DSL declarations — e.g. a page
  # declares params but no `page_path`, or `adds_children_to` receives a
  # Symbol that does not start with `@`.
  InvalidDefinition = Class.new(Error)

  # Raised for semantic mistakes at render / action time — invalid input
  # combinations or references to state that isn't there (e.g. an unknown
  # assets bundle named at `register_stylesheet`).
  InvalidUsage = Class.new(Error)

  # Raised by the `adds_children_to :@ivar` macro when build returns without
  # ever assigning the named ivar and then a child is added — almost always
  # means the developer declared the macro but forgot the matching assignment.
  MissingContainerIvar = Class.new(InvalidDefinition)
end
