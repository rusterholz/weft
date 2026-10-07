# frozen_string_literal: true

require "rack/mock_request"
require "sinatra/base"

require "weft/request"

RSpec.describe Weft::Request do
  def env_for(path = "/", **opts) = Rack::MockRequest.env_for(path, opts)
  def request_for(path = "/", **) = described_class.wrap(env_for(path, **))

  describe ".wrap" do
    it "hands back a Weft::Request unchanged" do
      request = request_for
      expect(described_class.wrap(request)).to equal(request)
    end

    it "wraps a Rack env" do
      expect(described_class.wrap(env_for("/orders")).path).to eq("/orders")
    end

    it "wraps a Rack request over the same env" do
      env = env_for("/orders")
      request = described_class.wrap(Rack::Request.new(env))
      expect(request.path).to eq("/orders")
      expect(request.env).to equal(env)
    end

    it "wraps a Sinatra request" do
      expect(described_class.wrap(Sinatra::Request.new(env_for("/a"))).path).to eq("/a")
    end

    it "makes an empty request of nil: a GET for / that sent nothing" do
      request = described_class.wrap(nil)
      expect([request.request_method, request.path, request.htmx?, request.cookies]).
        to eq(["GET", "/", false, {}])
      expect(request.header?("Accept")).to be(false)
      expect(request.url).to eq("http://localhost/")
    end

    it "refuses a Hash that is not a Rack env" do
      expect { described_class.wrap({ status: "shipped" }) }.to raise_error(ArgumentError, /Rack env/)
    end

    it "refuses anything else" do
      expect { described_class.wrap(Object.new) }.to raise_error(ArgumentError, /Weft::Request/)
    end
  end

  describe "#id" do
    it "adopts an id already in the env" do
      env = env_for("/", "weft.request_id" => "upstream-1", "HTTP_X_REQUEST_ID" => "header-1")
      expect(described_class.wrap(env).id).to eq("upstream-1")
    end

    it "adopts an inbound X-Request-Id" do
      expect(request_for("/", "HTTP_X_REQUEST_ID" => "abc-123@edge").id).to eq("abc-123@edge")
    end

    it "strips what an id may not carry from an inbound X-Request-Id" do
      expect(request_for("/", "HTTP_X_REQUEST_ID" => "abc 123<script>").id).to eq("abc123script")
    end

    it "caps an inbound X-Request-Id at 255 characters" do
      expect(request_for("/", "HTTP_X_REQUEST_ID" => "a" * 300).id).to eq("a" * 255)
    end

    it "generates one when the header sanitizes to nothing" do
      expect(request_for("/", "HTTP_X_REQUEST_ID" => "<>").id).to match(/\A\h{8}-\h{4}-/)
    end

    it "generates one when nothing came in" do
      expect(request_for.id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    end

    it "writes the id into the env, where anything sharing the env finds it" do
      env = env_for
      request = described_class.wrap(env)
      expect(env["weft.request_id"]).to eq(request.id)
      expect(described_class.wrap(env).id).to eq(request.id)
    end

    it "writes no rack. key" do
      env = env_for
      before = env.keys.grep(/\Arack\./)
      described_class.wrap(env)
      expect(env.keys.grep(/\Arack\./)).to eq(before)
    end
  end

  describe "#header and #header?" do
    let(:request) do
      request_for("/", "HTTP_AUTHORIZATION" => "Bearer t", "CONTENT_TYPE" => "text/plain")
    end

    it "reads a header by its HTTP name" do
      expect(request.header("Authorization")).to eq("Bearer t")
      expect(request.header("authorization")).to eq("Bearer t")
    end

    it "reads Content-Type, which Rack keeps unprefixed" do
      expect(request.header("Content-Type")).to eq("text/plain")
    end

    it "answers nil for a header that did not come" do
      expect(request.header("X-Missing")).to be_nil
    end

    it "tells a header that came from one that did not" do
      expect([request.header?("Authorization"), request.header?("X-Missing")]).to eq([true, false])
    end
  end

  describe "htmx" do
    let(:htmx_headers) do
      { "HTTP_HX_REQUEST" => "true", "HTTP_HX_TARGET" => "orders", "HTTP_HX_TRIGGER" => "btn-1",
        "HTTP_HX_TRIGGER_NAME" => "cancel", "HTTP_HX_CURRENT_URL" => "http://x/orders",
        "HTTP_HX_BOOSTED" => "true", "HTTP_HX_HISTORY_RESTORE_REQUEST" => "true", "HTTP_HX_PROMPT" => "yes" }
    end

    it "knows an htmx request by HX-Request: true" do
      expect(request_for("/", "HTTP_HX_REQUEST" => "true").htmx?).to be(true)
      expect(request_for("/", "HTTP_HX_REQUEST" => "false").htmx?).to be(false)
      expect(request_for.htmx?).to be(false)
    end

    it "reads htmx's request headers" do
      htmx = request_for("/", **htmx_headers).htmx
      expect([htmx.target, htmx.trigger, htmx.trigger_name, htmx.current_url, htmx.prompt]).
        to eq(%w[orders btn-1 cancel http://x/orders yes])
      expect([htmx.boosted?, htmx.history_restore?]).to eq([true, true])
    end

    it "answers nil and false on a request htmx did not send" do
      htmx = request_for.htmx
      expect([htmx.target, htmx.prompt, htmx.boosted?, htmx.history_restore?]).to eq([nil, nil, false, false])
    end
  end

  describe "the HTTP floor" do
    let(:request) do
      headers = { "HTTP_COOKIE" => "theme=dark", "HTTP_ACCEPT" => "text/html",
                  "HTTP_X_FORWARDED_FOR" => "203.0.113.9, 10.0.0.1", "REMOTE_ADDR" => "10.0.0.2" }
      request_for("https://shop.test/orders?page=2", method: "PATCH", **headers)
    end

    it "answers for method, location and negotiation" do
      expect([request.patch?, request.get?, request.path, request.fullpath, request.secure?, request.host]).
        to eq([true, false, "/orders", "/orders?page=2", true, "shop.test"])
      expect(request.accept?("text/html")).to be(true)
      expect([request.safe?, request.idempotent?]).to eq([false, false])
    end

    it "reads cookies" do
      expect(request.cookies).to eq("theme" => "dark")
    end

    it "reads the client address through trusted proxies, and says which are trusted" do
      expect(request.ip).to eq("203.0.113.9")
      expect(request.forwarded_for).to eq(["203.0.113.9", "10.0.0.1"])
      expect([request.trusted_proxy?("10.0.0.1"), request.trusted_proxy?("203.0.113.9")]).to eq([true, false])
    end

    it "exposes the Rack env" do
      expect(request.env["PATH_INFO"]).to eq("/orders")
    end
  end

  describe "what it refuses" do
    it "has no route around weft's params" do
      request = request_for("/?a=1", method: "POST", input: "b=2")
      refused = %i[params GET POST form_pairs parseable_data? form_data? body each_header query_string]
      expect(refused.select { |name| request.respond_to?(name) }).to be_empty
    end

    it "defers the mutators and the session" do
      deferred = %i[update_param delete_param path_info= script_name= query_parser= set_header add_header
                    delete_header session session_options]
      expect(deferred.select { |name| request_for.respond_to?(name) }).to be_empty
    end
  end

  describe "#logger" do
    it "is weft's logger" do
      expect(request_for.logger).to equal(Weft.logger)
    end
  end
end
