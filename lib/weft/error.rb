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

    # What status an exception reports on the wire — asked by the response the
    # router writes and by `from:` matching alike, so the two cannot disagree.
    # A weft error carries its own; a foreign one is asked whether it declares
    # an `http_status`, the convention Sinatra's and Rack's errors already
    # speak. Silence is a fault, not a client's mistake: an exception that says
    # nothing about itself reports 500, as does one naming a non-error status.
    def self.status_for(exception)
      declared = if exception.is_a?(HTTPError) then exception.status
                 elsif exception.respond_to?(:http_status) then exception.http_status
                 end
      declared.is_a?(Integer) && (400..599).cover?(declared) ? declared : 500
    end

    def status
      self.class.status
    end
  end

  # The request itself could not be read — a value no declared type can
  # represent, a required one absent. Distinct from Unprocessable (422), which
  # says weft read you fine and your domain said no; that judgment belongs to
  # the application's own validation, not here.
  class BadRequest < HTTPError
    def self.status = 400
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

  # Raised at render time when a value composing a component's DOM id is not a
  # scalar — an Array, a Hash, a record. Its own category on purpose: nothing is
  # missing and no API was misused, so it is neither an InvalidUsage nor an
  # InvalidDefinition. The declaration is legitimate and the value that reached
  # it cannot be addressed, and the fix is sometimes one and sometimes the other.
  InvalidIdentifierValue = Class.new(Error)

  # Raised for semantic mistakes at render / action time — invalid input
  # combinations or references to state that isn't there (e.g. an unknown
  # assets bundle named at `register_stylesheet`).
  InvalidUsage = Class.new(Error)

  # Raised by the bang forms of the render-tree lookup (`closest!` / `enclosing!`)
  # when no node matches the requested criteria — the component expected an
  # ancestor that isn't there (it should usually be `dependent!` and rendered
  # only inside that ancestor).
  AncestorNotFound = Class.new(InvalidUsage)

  # Raised at construction when the wire sent a value a param's declared type
  # cannot represent and the param is strict. Carries every violation from the
  # same pass — a form with three bad fields reports three, rather than making
  # the caller fix them one round-trip at a time — each naming the key, the raw
  # value as it arrived, and the type it failed. The raw value is the point:
  # a recovery redrawing a form needs what the user typed, not the zero lenient
  # coercion would have invented in its place.
  class InvalidParamValue < BadRequest
    attr_reader :violations

    def initialize(message, violations = [])
      super(message)
      @violations = violations
    end
  end

  # Raised at construction when a param declared `required: true` ends
  # resolution with no value from any source. The wire counterpart of
  # {NotReceived}, which guards the hand-off door — note the two doors default
  # opposite ways, since the wire is absent by nature and a hand-off is the
  # caller's contract.
  MissingParam = Class.new(BadRequest)

  # Raised by the `adds_children_to :@ivar` macro when build returns without
  # ever assigning the named ivar and then a child is added — almost always
  # means the developer declared the macro but forgot the matching assignment.
  MissingContainerIvar = Class.new(InvalidDefinition)

  # Raised at component construction when a `receives` key with no declared
  # default ends resolution valueless — the call site didn't hand it over and
  # no other source (wire dual, inherited bag) supplied it.
  NotReceived = Class.new(InvalidUsage)

  # Raised when a verb block reads a key whose only door is `receives`, from a
  # bag assembled where no call site exists to hand one over — a request has
  # composed its state, but nothing has been built yet. A declared default
  # still answers on those paths, so what reaches here is the key a caller
  # alone could have supplied. Distinct from {NotReceived}, where a call site
  # did run and left the value out: there the fix is to pass it, here it is to
  # give the key a source that does not need a caller.
  UnreachableHandoff = Class.new(InvalidUsage)
end
