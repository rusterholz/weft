# frozen_string_literal: true

require "forwardable"
require "securerandom"
require "sinatra/base"
require "stringio"

require "weft/error"
require "weft/request/htmx"

module Weft
  # One inbound HTTP request, as weft code sees it: a component's `build`, a
  # page's, or a verb block. It wraps the Rack request rather than replacing
  # it, and answers for the HTTP floor (method, location, headers, content
  # type, negotiation, cookies, the client's address), htmx's request headers,
  # and an id that ties every log line and response of one request together.
  #
  # What it leaves out is the route around weft's params: raw params, the
  # body, the query string. Values a request sends reach your code through
  # `params`, validated and coerced. The Rack `env` stays reachable for
  # anything the curated surface does not cover.
  class Request
    extend Forwardable

    # Where the id lives in the Rack env, for anything sharing the env.
    ID_KEY = "weft.request_id"

    # Rails' rule for an inbound X-Request-Id: word characters, `-` and `@`.
    ID_REFUSED = /[^\w\-@]/
    ID_LIMIT = 255
    private_constant :ID_REFUSED, :ID_LIMIT

    # Headers Rack stores without the HTTP_ prefix.
    UNPREFIXED = %w[CONTENT_TYPE CONTENT_LENGTH].freeze
    private_constant :UNPREFIXED

    def_delegators :@request,
                   # method
                   :request_method, :get?, :head?, :post?, :put?, :patch?, :delete?, :options?, :trace?,
                   :link?, :unlink?, :safe?, :idempotent?, :xhr?,
                   # location
                   :scheme, :ssl?, :secure?, :url, :base_url, :fullpath, :path, :path_info, :script_name,
                   :host, :hostname, :host_with_port, :port, :authority, :host_authority, :server_authority,
                   :server_name, :server_port, :forwarded?, :forwarded_port, :referer, :referrer,
                   :user_agent,
                   # content type
                   :content_type, :media_type, :media_type_params, :content_charset, :content_length,
                   # negotiation
                   :accept, :accept?, :preferred_type, :accept_encoding, :accept_language,
                   # client
                   :cookies, :ip, :forwarded_for, :forwarded_authority, :trusted_proxy?,
                   :env

    class << self
      # A Weft::Request for whatever stands for a request here: a Weft::Request
      # (as is), a Rack or Sinatra request or anything else carrying a Rack
      # `env`, a Rack env itself, or nil for an empty request, a GET for `/`
      # that sent nothing.
      def wrap(request)
        case request
        when Weft::Request then request
        when nil then new(Sinatra::Request.new(empty_env))
        when Sinatra::Request then new(request)
        when Hash then new(Sinatra::Request.new(rack_env!(request)))
        else
          raise ArgumentError, unwrappable(request) unless request.respond_to?(:env)

          new(Sinatra::Request.new(request.env))
        end
      end

      private

      def rack_env!(hash)
        return hash if hash.key?("REQUEST_METHOD")

        raise ArgumentError, "a Hash given as a request must be a Rack env (it has no REQUEST_METHOD): " \
                             "#{hash.inspect}"
      end

      def unwrappable(request)
        "can't make a Weft::Request of #{request.inspect}: pass a Weft::Request, a Rack request, " \
          "a Rack env, or nil for an empty request"
      end

      def empty_env
        { "REQUEST_METHOD" => "GET", "SCRIPT_NAME" => "", "PATH_INFO" => "/", "QUERY_STRING" => "",
          "SERVER_NAME" => "localhost", "SERVER_PORT" => "80", "SERVER_PROTOCOL" => "HTTP/1.1",
          "rack.url_scheme" => "http", "rack.input" => StringIO.new(+"") }
      end
    end

    # Use .wrap: it knows what to make of each kind of request.
    def initialize(request)
      @request = request
      @id = adopt_id
    end

    # This request's id: one already in the env, else the client's (or a
    # proxy's) X-Request-Id with anything unsafe stripped, else a fresh UUID.
    # Every push on a stream answers with the id of the request that opened it.
    attr_reader :id

    # Weft's logger.
    def logger = Weft.logger

    # A request header by its HTTP name, any case: `header("Authorization")`.
    def header(name) = @request.get_header(rack_key(name))

    # Whether the request sent the header at all.
    def header?(name) = @request.has_header?(rack_key(name))

    # Whether htmx made this request.
    def htmx? = header("HX-Request") == "true"

    # htmx's request headers: `request.htmx.target`, `.trigger`, `.prompt`...
    def htmx = @htmx ||= Htmx.new(self)

    private

    # @api private
    # Everything the client sent, undeclared keys included, plus the matched
    # route's path params, which outrank a query value of the same name. Each
    # component projects it through its own declarations. Frozen and computed
    # once: every bag of the exchange carries this one object. Private, and
    # reached with `send`: it is the raw wire that `params` exists to replace.
    def universe
      @universe ||= Sinatra::IndifferentHash[@request.params].merge(@route_params || {}).freeze
    end

    # @api private
    # The path params of the page route this request matched, said once, by
    # whoever matched it, before anything reads the universe.
    def record_route_params(params)
      if @route_params || @universe
        raise Weft::InvalidUsage, "route params are recorded once, before the universe is read"
      end

      @route_params = params.to_h { |key, value| [key.to_s, value] }
    end

    # @api private
    # A request whose body or query could not be parsed sent nothing weft can
    # read, so its universe is empty rather than raising again at every read.
    def unreadable!
      @universe = {}.freeze
    end

    def adopt_id
      env = @request.env
      existing = env[ID_KEY]
      return existing unless existing.to_s.empty?

      env[ID_KEY] = inbound_id || SecureRandom.uuid
    end

    def inbound_id
      cleaned = header("X-Request-Id").to_s.gsub(ID_REFUSED, "")[0, ID_LIMIT]
      cleaned unless cleaned.empty?
    end

    def rack_key(name)
      key = name.to_s.upcase.tr("-", "_")
      UNPREFIXED.include?(key) ? key : "HTTP_#{key}"
    end
  end
end
