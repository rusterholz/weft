# frozen_string_literal: true

require "rack/test"

RSpec.describe Weft::Router do
  include Rack::Test::Methods

  # A simple downstream app that returns 200 for its own routes
  let(:downstream_app) do
    ->(_env) { [200, { "content-type" => "text/plain" }, ["downstream"]] }
  end
  # Eagerly define so the class registers with the Registry via `inherited`
  let!(:stat_card_class) do
    klass = Class.new(Weft::Component) do
      def self.name = "StatCard"
      param :status, default: "all"
      param :value, default: 0

      def build(attributes = {})
        super
        div(class: "stat-card") do
          span(class: "status") { text_node params[:status] }
          span(class: "value") { text_node params[:value].to_s }
        end
      end
    end
    klass
  end

  let(:app) do
    described_class.set :environment, :test
    described_class.new(downstream_app)
  end

  describe "component partial routes" do
    it "renders a component at its derived path" do
      get "/_components/stat_card", status: "shipped", value: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
      expect(last_response.body).to include("shipped")
      expect(last_response.body).to include("42")
    end

    it "returns an HTML fragment, not a full document" do
      get "/_components/stat_card"

      expect(last_response.body).not_to include("<!DOCTYPE")
      expect(last_response.body).not_to include("<html")
      expect(last_response.body).to include("<div")
    end

    it "applies param defaults for missing params" do
      get "/_components/stat_card"

      expect(last_response.body).to include("all")
      expect(last_response.body).to include("0")
    end

    it "coerces params via the Resolver" do
      get "/_components/stat_card", value: "99"

      expect(last_response.body).to include("99")
    end

    it "sets the component DOM ID" do
      get "/_components/stat_card", status: "shipped"

      expect(last_response.body).to include('id="stat-card-shipped"')
    end
  end

  describe "namespace-derived routes" do
    let!(:namespaced_class) do # rubocop:disable RSpec/LetSetup
      Class.new(Weft::Component) do
        def self.name = "Oms::OrderHeader"
        param :order_id

        def build(attributes = {})
          super
          div { text_node "order-#{params[:order_id]}" }
        end
      end
    end

    it "routes namespaced components under their derived path" do
      get "/_components/oms/order_header", order_id: "7"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("order-7")
    end
  end

  describe "action routes" do
    let!(:order_header_class) do # rubocop:disable RSpec/LetSetup
      Class.new(Weft::Component) do
        def self.name = "OrderHeader"
        param :order_id
        param :status, default: "pending"

        performs(:advance) do |_params|
          { status: "advanced" }
        end

        performs(:noop) { nil }

        performs(method: :delete, swap: :delete) { nil }

        def build(attributes = {})
          super
          div(class: "order-header") do
            span(class: "status") { text_node params.status }
          end
        end
      end
    end

    it "routes POST to a named action and re-renders the component" do
      post "/_components/order_header/advance", order_id: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
      expect(last_response.body).to include("order-header")
    end

    it "merges the callable's return hash into params for re-render" do
      post "/_components/order_header/advance", order_id: "42"

      expect(last_response.body).to include("advanced")
    end

    it "uses original params when callable returns nil" do
      post "/_components/order_header/noop", order_id: "42"

      expect(last_response.body).to include("pending")
    end

    it "routes nameless actions at the root path by HTTP method" do
      delete "/_components/order_header", order_id: "42"

      expect(last_response.status).to eq(200)
    end

    it "returns 404 for unknown action names" do
      post "/_components/order_header/nonexistent", order_id: "1"

      # Falls through to downstream app since no action matched
      expect(last_response.body).to eq("downstream")
    end

    it "returns 404 for wrong HTTP method on a named action" do
      get "/_components/order_header/advance", order_id: "1"

      expect(last_response.body).to eq("downstream")
    end
  end

  describe "transfers routes" do
    let!(:read_only_class) do
      Class.new(Weft::Component) do
        def self.name = "ReadOnlyCard"
        param :order_id

        def build(attributes = {})
          super
          div { text_node "read-only-#{params.order_id}" }
        end
      end
    end

    let!(:editable_class) do
      Class.new(Weft::Component) do
        def self.name = "EditableCard"
        param :order_id
        param :mode, default: "edit"

        def build(attributes = {})
          super
          div { text_node "editable-#{params.order_id}-#{params.mode}" }
        end
      end
    end

    before do
      target = editable_class
      read_only_class.transfers(:edit, to: target) { |_params| { mode: "full" } }
    end

    it "renders the target component instead of self" do
      post "/_components/read_only_card/edit", order_id: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("editable-42")
    end

    it "merges the block's return hash into params for the target" do
      post "/_components/read_only_card/edit", order_id: "42"

      expect(last_response.body).to include("editable-42-full")
    end

    it "passes through params when no block is given" do
      target = editable_class
      # Define a second transfer without a block
      read_only_class.transfers(:quick_edit, to: target)

      post "/_components/read_only_card/quick_edit", order_id: "7"

      expect(last_response.body).to include("editable-7-edit")
    end
  end

  describe "cross-component-class param isolation" do
    let!(:contact_card_class) do
      Class.new(Weft::Component) do
        def self.name = "ContactCard"
        param :contact_id
        param :headline, default: "Contact"

        def build(attributes = {})
          super
          div(class: "contact-card") { text_node "#{params.headline}-#{params.contact_id}" }
        end
      end
    end

    let!(:contact_editor_class) do
      Class.new(Weft::Component) do
        def self.name = "ContactEditor"
        param :contact_id
        param :first_name, default: "Joseph"
        param :last_name, default: "Blow"
        param :email, default: "joe@blow.com"

        def build(attributes = {})
          super
          div(class: "contact-editor") { text_node "editing-#{params.contact_id}" }
        end
      end
    end

    before do
      target = contact_card_class
      contact_editor_class.transfers(:save, to: target)
    end

    it "does not splat the declaring component's undeclared params onto the rendered target" do
      post "/_components/contact_editor/save", contact_id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("contact-card")
      # ContactCard does not declare these — they must not surface as HTML attributes.
      expect(last_response.body).not_to include("first_name=")
      expect(last_response.body).not_to include("last_name=")
      expect(last_response.body).not_to include("email=")
    end

    it "carries the target's shared params and applies the target's defaults for absent keys" do
      post "/_components/contact_editor/save", contact_id: "1"

      # contact_id shared → present; headline absent from the bag → target default.
      expect(last_response.body).to include("Contact-1")
    end

    it "does not leak performs callable keys the component does not declare" do
      Class.new(Weft::Component) do
        def self.name = "PerformsLeakCard"
        param :id

        performs(:go) { |_params| { id: "kept", surprise: "leak" } }

        def build(attributes = {})
          super
          div { text_node "id=#{params.id}" }
        end
      end

      post "/_components/performs_leak_card/go", id: "1"

      # Declared key the callable updated survives; undeclared key does not leak.
      expect(last_response.body).to include("id=kept")
      expect(last_response.body).not_to include("surprise")
    end
  end

  describe "class-level triggers" do
    let!(:triggering_class) do # rubocop:disable RSpec/LetSetup
      Class.new(Weft::Component) do
        def self.name = "TriggerTest"
        param :id
        triggers "item-updated"
        performs(:save) { nil }
      end
    end

    it "sets HX-Trigger header on action responses" do
      post "/_components/trigger_test/save", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["HX-Trigger"]).to eq("item-updated")
    end

    it "supports multiple triggers" do
      Class.new(Weft::Component) do
        def self.name = "MultiTrigger"
        param :id
        triggers "event-a"
        triggers "event-b"
        performs(:go) { nil }
      end

      post "/_components/multi_trigger/go", id: "1"

      header = last_response.headers["HX-Trigger"]
      expect(header).to include("event-a")
      expect(header).to include("event-b")
    end

    it "does not set HX-Trigger on plain GET renders" do
      get "/_components/trigger_test", id: "1"

      expect(last_response.headers).not_to have_key("HX-Trigger")
    end
  end

  describe "error handling" do
    let!(:failing_class) do # rubocop:disable RSpec/LetSetup
      Class.new(Weft::Component) do
        def self.name = "FailingCard"
        param :id

        def build(attributes = {})
          super
          raise "something broke"
        end
      end
    end

    it "returns 500 and renders the gem-default ErrorComponent when rendering fails" do
      get "/_components/failing_card", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("Something went wrong")
      expect(last_response.body).to include("RuntimeError")
      expect(last_response.body).to include("something broke")
    end

    it "preserves the failing component's DOM id via the :component_id auto-injected param" do
      get "/_components/failing_card", id: "1"
      expect(last_response.body).to include('id="failing-card-1"')
    end

    it "includes a retry button targeting the failing wrapper" do
      get "/_components/failing_card", id: "1"

      expect(last_response.body).to include("Retry")
      expect(last_response.body).to include('hx-get="/_components/failing_card?id=1"')
      expect(last_response.body).to include('hx-target="closest .weft-error"')
      expect(last_response.body).to include('hx-swap="outerHTML"')
      expect(last_response.body).to include('hx-trigger="click"')
    end

    it "falls back to a generic retry box when the recovery render itself fails" do # rubocop:disable RSpec/ExampleLength
      original = Weft.configuration.error_component
      Weft.configuration.error_component = Class.new(Weft::Component) do
        def self.name = "BoomError"
        abstract!
        def build(_ = {})
          super
          raise "recovery boom"
        end
      end
      Class.new(Weft::Component) do
        def self.name = "DoublyFailing"
        param :id
        def build(_ = {})
          super
          raise "primary boom"
        end
      end

      get "/_components/doubly_failing", id: "7"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("Retry")
      expect(last_response.body).to include('hx-get="/_components/doubly_failing?id=7"')
      expect(last_response.body).to include('hx-target="closest .weft-error"')
      expect(last_response.body).to include('hx-swap="outerHTML"')
    ensure
      Weft.configuration.error_component = original
    end

    it "renders ErrorComponent with status 500 when an action fails" do
      Class.new(Weft::Component) do
        def self.name = "ActionFail"
        param :id
        performs(:explode) { |_| raise "boom" }
      end

      post "/_components/action_fail/explode", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("Something went wrong")
      expect(last_response.body).to include("RuntimeError")
      expect(last_response.body).to include("boom")
    end

    it "re-renders self with augmented params from a recovers block" do # rubocop:disable RSpec/ExampleLength
      Class.new(Weft::Component) do
        def self.name = "RecoverableCard"
        param :id
        param :error_message

        recovers(from: StandardError) { |_params, error| { error_message: error.message } }

        def build(attributes = {})
          super
          raise "oops" unless params.error_message

          div(class: "custom-error") { text_node "Recovered: #{params.error_message}" }
        end
      end

      get "/_components/recoverable_card", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("custom-error")
      expect(last_response.body).to include("Recovered: oops")
      expect(last_response.body).not_to include("Retry")
    end

    it "inherits recovers entries from parent class" do # rubocop:disable RSpec/ExampleLength
      parent = Class.new(Weft::Component) do
        def self.name = "BaseRecoverable"
        recovers(from: StandardError) { |_params, error| { error_message: error.message } }
      end
      Class.new(parent) do
        def self.name = "ChildRecoverable"
        param :id
        param :error_message

        def build(attributes = {})
          super
          raise "child error" unless params.error_message

          span "parent-recovery: #{params.error_message}"
        end
      end

      get "/_components/child_recoverable", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("parent-recovery: child error")
    end
  end

  describe "SSE stream routing" do
    before do
      Class.new(Weft::Component) do
        def self.name = "PushCard"
        param :order_id
        pushes every: 5

        def build(attributes = {})
          super
          span(class: "content") { text_node "order-#{params.order_id}" }
        end
      end
    end

    # NOTE: stream :keep_open blocks Rack::Test (the loop never returns),
    # so we can't test content-type or SSE wire format here. Those are
    # verified via the demo's manual SSE endpoint. These tests confirm
    # routing and passthrough behavior.

    it "passes through for components without push config" do
      get "/_components/stat_card/_stream"

      expect(last_response.body).to eq("downstream")
    end

    it "passes through for unknown component paths" do
      get "/_components/nonexistent/_stream"

      expect(last_response.body).to eq("downstream")
    end

    it "does not interfere with normal GET routes" do
      get "/_components/stat_card", status: "shipped"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("shipped")
    end
  end

  describe "stream_component first-frame delivery" do
    # Drives stream_component directly (Rack::Test can't run the keep-open loop):
    # stub stream/sleep/push to record call order, raise IOError to break the loop.
    let(:pushing_class) do
      Class.new(Weft::Component) do
        def self.name = "ImmediatePushCard"
        pushes every: 5
      end
    end

    it "pushes the first frame immediately, then sleeps before subsequent frames" do
      router = described_class.new!(downstream_app)
      order = []
      allow(router).to receive(:content_type)
      allow(router).to receive(:headers)
      allow(router).to receive(:stream).and_yield([])
      allow(router).to receive(:sleep) { order << :sleep }
      allow(router).to receive(:push_component_event) do
        order << :push
        raise IOError if order.count(:push) >= 2
      end

      router.send(:stream_component, pushing_class)

      expect(order).to eq(%i[push sleep push])
    end
  end

  describe "configurable stream suffix" do
    around do |example|
      original = Weft.configuration.stream_suffix
      example.run
    ensure
      Weft.configuration.stream_suffix = original
    end

    it "treats a path ending in the configured suffix as a stream request" do
      Weft.configuration.stream_suffix = "sse"
      router = described_class.new!(downstream_app)

      expect(router.send(:stream_request?, "/_components/push_card/sse")).to be(true)
      expect(router.send(:stream_request?, "/_components/push_card/stream")).to be(false)
    end

    it "strips the configured suffix to locate the streaming component" do
      Weft.configuration.stream_suffix = "sse"
      pushing = Class.new(Weft::Component) do
        def self.name = "ConfiguredPush"
        pushes every: 5
      end
      router = described_class.new!(downstream_app)
      streamed = nil
      allow(router).to receive(:pass)
      allow(router).to receive(:stream_component) { |klass| streamed = klass }

      router.send(:handle_stream_request, "/_components/configured_push/sse")

      expect(streamed).to eq(pushing)
    end
  end

  describe "build_component_with_params_as_attrs" do
    it "builds a component instance with resolved attributes" do
      router = described_class.new!(downstream_app)
      component = router.send(:build_component_with_params_as_attrs, stat_card_class, { status: "shipped", value: 10 })

      expect(component).to be_a(Weft::Component)
      expect(component.weft_id).to eq("stat-card-shipped")
      expect(component.content).to include("shipped")
      expect(component.to_s).to include('id="stat-card-shipped"')
    end

    it "returns children-only HTML via content (for SSE innerHTML swap)" do
      router = described_class.new!(downstream_app)
      component = router.send(:build_component_with_params_as_attrs, stat_card_class, { status: "shipped", value: 10 })

      # content returns children only — no wrapper div
      expect(component.content).not_to include('id="stat-card-shipped"')
      expect(component.content).to include("shipped")
      expect(component.content).to include("10")

      # to_s returns the full component including wrapper
      expect(component.to_s).to include('id="stat-card-shipped"')
    end
  end

  describe "OOB includes in action responses" do
    let!(:included_class) do
      Class.new(Weft::Component) do
        def self.name = "IncludedHeader"
        param :order_id

        def build(attributes = {})
          super
          span "header-for-#{params.order_id}"
        end
      end
    end

    let!(:including_class) do
      target = included_class
      Class.new(Weft::Component) do
        def self.name = "IncludingCard"
        param :order_id
        performs(:refresh_all) { nil }

        define_method(:__included_target) { target }
      end
    end

    before { including_class.includes(included_class) }

    it "appends OOB-swapped component to action responses" do
      post "/_components/including_card/refresh_all", order_id: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('hx-swap-oob="true"')
      expect(last_response.body).to include("header-for-42")
    end

    it "respects on: filter — includes only for matching actions" do
      filtered_class = included_class
      source = Class.new(Weft::Component) do
        def self.name = "FilteredInc"
        param :order_id
        performs(:advance) { nil }
        performs(:noop) { nil }
      end
      source.includes(filtered_class, on: :advance)

      post "/_components/filtered_inc/advance", order_id: "7"
      expect(last_response.body).to include('hx-swap-oob="true"')

      post "/_components/filtered_inc/noop", order_id: "7"
      expect(last_response.body).not_to include('hx-swap-oob="true"')
    end

    it "supports block for explicit attr mapping" do
      mapped_class = included_class
      source = Class.new(Weft::Component) do
        def self.name = "MappedInc"
        param :id
        performs(:go) { nil }
      end
      source.includes(mapped_class) { |params| { order_id: params[:id] } }

      post "/_components/mapped_inc/go", id: "99"

      expect(last_response.body).to include("header-for-99")
      expect(last_response.body).to include('hx-swap-oob="true"')
    end

    it "passes callable-returned keys through the accumulated bag to inclusion blocks" do
      sink = included_class
      source = Class.new(Weft::Component) do
        def self.name = "BagSource"
        param :order_id
        # :note is not declared — it only exists on the accumulated bag because
        # the callable returned it. The inclusion block must still see it.
        performs(:go) { |_params| { note: "from-callable" } }
      end
      source.includes(sink) { |params| { order_id: params[:note] } }

      post "/_components/bag_source/go", order_id: "1"

      expect(last_response.body).to include("header-for-from-callable")
      expect(last_response.body).to include('hx-swap-oob="true"')
    end
  end

  describe "dismisses error handling" do
    it "sets HX-Reswap on error for delete swap actions" do
      Class.new(Weft::Component) do
        def self.name = "DismissError"
        param :id
        dismisses(:remove) { |_| raise "side effect failed" }
      end

      delete "/_components/dismiss_error/remove", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.headers["HX-Reswap"]).to eq("outerHTML")
      expect(last_response.body).to include("side effect failed")
    end

    it "does not set HX-Reswap for non-delete actions" do
      Class.new(Weft::Component) do
        def self.name = "NormalError"
        param :id
        performs(:explode) { |_| raise "boom" }
      end

      post "/_components/normal_error/explode", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.headers).not_to have_key("HX-Reswap")
    end
  end

  describe "Redirect handling" do
    before do
      Class.new(Weft::Component) do
        def self.name = "RedirectComp"
        param :id

        performs(:submit) { Weft::Redirect.to("/success/42") }
        performs(:noop) { nil }
        performs(:merge) { { id: "merged" } }

        def build(attributes = {})
          super
          span "id=#{params.id}"
        end
      end
    end

    it "sends HX-Redirect header for htmx requests" do
      post "/_components/redirect_comp/submit", { id: "1" },
           "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(204)
      expect(last_response.headers["HX-Redirect"]).to eq("/success/42")
    end

    it "sends 302 redirect for traditional (non-htmx) requests" do
      post "/_components/redirect_comp/submit", id: "1"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/success/42")
    end

    it "still re-renders when callable returns nil" do
      post "/_components/redirect_comp/noop", id: "7"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("id=7")
    end

    it "still merges params when callable returns a Hash" do
      post "/_components/redirect_comp/merge", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("id=merged")
    end
  end

  describe "recovers with Page target" do
    let!(:error_page) do
      Class.new(Weft::Page) do
        def self.name = "RecoverErrorPage"
        self.page_path = "/error-page"
      end
    end

    it "emits HX-Redirect for htmx requests when target is a Page" do
      target = error_page
      Class.new(Weft::Component) do
        def self.name = "RecoverRedirectHtmx"
        param :id

        recovers(from: StandardError, with: target)

        def build(attributes = {})
          super
          raise "oops"
        end
      end

      get "/_components/recover_redirect_htmx", { id: "1" }, "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(204)
      expect(last_response.headers["HX-Redirect"]).to eq("/error-page")
    end

    it "emits 302 redirect for traditional requests when target is a Page" do
      target = error_page
      Class.new(Weft::Component) do
        def self.name = "RecoverRedirectTrad"
        param :id

        recovers(from: StandardError, with: target)

        def build(attributes = {})
          super
          raise "oops"
        end
      end

      get "/_components/recover_redirect_trad", id: "1"

      expect(last_response.status).to eq(302)
      expect(last_response.headers["Location"]).to end_with("/error-page")
    end
  end

  describe "recovers status from HTTPError" do
    it "reports HTTPError's status on the wire when matched" do
      Class.new(Weft::Component) do
        def self.name = "HTTPErrorCard"
        param :id
        param :error_message

        recovers(from: Weft::HTTPError) { |_params, error| { error_message: error.message } }

        def build(attributes = {})
          super
          raise Weft::Unauthorized, "auth required" unless params.error_message

          div { text_node "recovered: #{params.error_message}" }
        end
      end

      get "/_components/http_error_card", id: "1"

      expect(last_response.status).to eq(401)
      expect(last_response.body).to include("recovered: auth required")
    end

    it "reports 500 for non-HTTPError exceptions even when matched" do
      Class.new(Weft::Component) do
        def self.name = "PlainErrorCard"
        param :id
        param :error_message

        recovers(from: StandardError) { |_params, error| { error_message: error.message } }

        def build(attributes = {})
          super
          raise "plain crash" unless params.error_message

          div { text_node "recovered: #{params.error_message}" }
        end
      end

      get "/_components/plain_error_card", id: "1"

      expect(last_response.status).to eq(500)
    end

    it "reports HTTPError's status when no recovers matches (generic path)" do
      Class.new(Weft::Component) do
        def self.name = "UnhandledHTTPError"
        param :id

        def build(attributes = {})
          super
          raise Weft::Forbidden, "no access"
        end
      end

      get "/_components/unhandled_http_error", id: "1"

      expect(last_response.status).to eq(403)
    end
  end

  describe "recovers auto-injected attributes (schema-gated)" do
    it "injects :exception when the target declares it" do
      Class.new(Weft::Component) do
        def self.name = "InjectsException"
        param :id
        param :exception

        recovers(from: StandardError)

        def build(attributes = {})
          super
          raise "boom" unless params.exception

          div(class: "got-exception") { text_node "class=#{params.exception.class}" }
        end
      end

      get "/_components/injects_exception", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("got-exception")
      expect(last_response.body).to include("class=RuntimeError")
    end

    it "injects :request_path when the target declares it" do
      Class.new(Weft::Component) do
        def self.name = "InjectsPath"
        param :id
        param :request_path

        recovers(from: StandardError)

        def build(attributes = {})
          super
          raise "boom" unless params.request_path

          div(class: "got-path") { text_node "at=#{params.request_path}" }
        end
      end

      get "/_components/injects_path", id: "1"

      expect(last_response.body).to include("at=/_components/injects_path")
    end

    it "injects :component_id when the target declares it — preserving the failing element's id" do
      Class.new(Weft::Component) do
        def self.name = "InjectsCompId"
        param :id
        param :component_id

        recovers(from: StandardError)

        def build(attributes = {})
          super
          raise "boom" unless params.component_id

          div(class: "got-comp-id") { text_node "id=#{params.component_id}" }
        end
      end

      get "/_components/injects_comp_id", id: "1"

      expect(last_response.body).to include("got-comp-id")
      expect(last_response.body).to include("id=injects-comp-id-1")
    end

    it "injects :retry_url when the target declares it — pointing at the component's GET URL with params" do
      Class.new(Weft::Component) do
        def self.name = "InjectsRetry"
        param :id
        param :retry_url

        recovers(from: StandardError)

        def build(attributes = {})
          super
          raise "boom" unless params.retry_url

          div(class: "got-retry") { text_node "url=#{params.retry_url}" }
        end
      end

      get "/_components/injects_retry", id: "42"

      expect(last_response.body).to include("url=/_components/injects_retry?id=42")
    end

    it "injects :status_code when the target declares it" do
      Class.new(Weft::Component) do
        def self.name = "InjectsStatus"
        param :id
        param :status_code

        recovers(from: Weft::HTTPError)

        def build(attributes = {})
          super
          raise Weft::Unprocessable, "bad input" unless params.status_code

          div(class: "got-status") { text_node "status=#{params.status_code}" }
        end
      end

      get "/_components/injects_status", id: "1"

      expect(last_response.body).to include("got-status")
      expect(last_response.body).to include("status=422")
    end

    it "does not inject auto-injected attributes the target did not declare" do # rubocop:disable RSpec/ExampleLength
      Class.new(Weft::Component) do
        def self.name = "PartialCarveouts"
        param :id
        param :exception
        # :request_path and :status_code intentionally NOT declared

        recovers(from: StandardError)

        def build(attributes = {})
          super
          raise "boom" unless params.exception

          div(class: "rendered-ok") { text_node "ok" }
        end
      end

      get "/_components/partial_carveouts", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("rendered-ok")
      # Carve-outs not declared on target must NOT appear as wrapper params.
      expect(last_response.body).not_to include("request_path=")
      expect(last_response.body).not_to include("status_code=")
    end

    it "suppresses :exception on the redirect path even if the Page declares it" do # rubocop:disable RSpec/ExampleLength
      target_page = Class.new(Weft::Page) do
        def self.name = "RedirectErrorPage2"
        self.page_path = "/redirect-error"
        param :exception
        param :request_path
      end
      target = target_page
      Class.new(Weft::Component) do
        def self.name = "RedirectsToPage"
        param :id

        recovers(from: StandardError, with: target)

        def build(attributes = {})
          super
          raise "boom"
        end
      end

      get "/_components/redirects_to_page", { id: "1" }, "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(204)
      expect(last_response.headers["HX-Redirect"]).to start_with("/redirect-error")
      # request_path declared on target → ends up in query string.
      expect(last_response.headers["HX-Redirect"]).to include("request_path=")
      # exception declared on target but should NOT survive into the URL.
      expect(last_response.headers["HX-Redirect"]).not_to include("exception=")
    end
  end

  describe "recovers block result merging" do
    it "merges block-returned params into the render" do # rubocop:disable RSpec/ExampleLength
      Class.new(Weft::Component) do
        def self.name = "BlockMerge"
        param :id
        param :reason
        param :hint

        recovers(from: StandardError) do |_params, error|
          { reason: error.message, hint: "try again" }
        end

        def build(attributes = {})
          super
          raise "first failure" unless params.reason

          div { text_node "#{params.reason} / #{params.hint}" }
        end
      end

      get "/_components/block_merge", id: "1"

      expect(last_response.body).to include("first failure / try again")
    end
  end

  describe "recovery target param isolation" do
    it "does not leak the failing component's undeclared params onto a cross-class recovery component" do # rubocop:disable RSpec/ExampleLength
      recovery_target = Class.new(Weft::Component) do
        def self.name = "RecoveryTargetCard"
        param :id
        param :exception

        def build(attributes = {})
          super
          div(class: "recovery-target") { text_node "recovered-#{params.id}-#{params.exception&.class}" }
        end
      end
      target = recovery_target
      Class.new(Weft::Component) do
        def self.name = "FailingWithSecret"
        param :id
        param :secret

        recovers(from: StandardError, with: target)

        def build(attributes = {})
          super
          raise "boom"
        end
      end

      get "/_components/failing_with_secret", id: "1", secret: "sensitive"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include("recovery-target")
      # Declared auto-attr still injected and rendered on the target.
      expect(last_response.body).to include("recovered-1-RuntimeError")
      # The failing component's :secret is undeclared on the target — no leak.
      expect(last_response.body).not_to include("secret=")
      expect(last_response.body).not_to include("sensitive")
    end

    it "does not leak the originating page's undeclared params onto a cross-class recovery page" do # rubocop:disable RSpec/ExampleLength
      recovery_page = Class.new(Weft::Page) do
        def self.name = "PageRecoveryTarget"
        self.page_path = "/page-recovery-target"

        def build(attributes = {})
          super
          div(class: "recovery-page") { text_node "recovery-page-body" }
        end
      end
      target = recovery_page
      Class.new(Weft::Page) do
        def self.name = "FailingOriginPage"
        self.page_path = "/failing-origin/:order_id"
        param :order_id

        recovers(from: StandardError, with: target)

        def build(attributes = {})
          super
          raise "page boom"
        end
      end

      get "/failing-origin/42"

      expect(last_response.body).to include("recovery-page-body")
      # order_id belongs to the originating page's schema, not the recovery
      # page's — it must not land on the <html> element.
      expect(last_response.body).not_to include("order_id=")
    end
  end

  describe "routable? filtering" do
    before do
      Class.new(Weft::Component) do
        def self.name = "NonRoutable"

        def build(attributes = {})
          super
          span "I am not routable"
        end
      end
    end

    it "passes through non-routable components on GET" do
      get "/_components/non_routable"

      expect(last_response.body).to eq("downstream")
    end

    it "passes through non-routable components on POST" do
      post "/_components/non_routable"

      expect(last_response.body).to eq("downstream")
    end

    it "still serves routable components" do
      get "/_components/stat_card", status: "shipped"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("shipped")
    end
  end

  describe "page routing" do
    before do
      Class.new(Weft::Page) do
        def self.name = "TestRoutedPage"
        self.page_path = "/test-pages/:item_id"
        param :item_id

        def build(attributes = {})
          super(attributes.merge(title: "Test Page"))
          div { text_node "page-item-#{params.item_id}" }
        end
      end
    end

    it "renders a page at its declared path" do
      get "/test-pages/42"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("page-item-42")
    end

    it "returns a full HTML document with DOCTYPE" do
      get "/test-pages/42"

      expect(last_response.body).to start_with("<!DOCTYPE html>")
      expect(last_response.body).to include("<html")
    end

    it "extracts route params as page attributes" do
      get "/test-pages/abc-123"

      expect(last_response.body).to include("page-item-abc-123")
    end

    it "passes through for unmatched page paths" do
      get "/no-such-page/1"

      expect(last_response.body).to eq("downstream")
    end

    it "does not serve pages on POST" do
      post "/test-pages/42"

      expect(last_response.body).to eq("downstream")
    end

    it "resolves query-string params into page attributes" do
      Class.new(Weft::Page) do
        def self.name = "QueryParamPage"
        self.page_path = "/query-page"
        param :filter
        param :page_num, default: 1

        def build(attributes = {})
          super
          div { text_node "filter=#{params.filter} page=#{params.page_num}" }
        end
      end

      get "/query-page?filter=active&page_num=3"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("filter=active page=3")
    end

    it "lets path params override query params with the same name" do
      Class.new(Weft::Page) do
        def self.name = "OverridePage"
        self.page_path = "/override/:slug"
        param :slug

        def build(attributes = {})
          super
          div { text_node "slug=#{params.slug}" }
        end
      end

      get "/override/from-path?slug=from-query"

      expect(last_response.body).to include("slug=from-path")
    end
  end

  describe "middleware passthrough" do
    it "passes unmatched requests to the downstream app" do
      get "/some/other/route"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("downstream")
    end
  end

  describe "standalone Rack-app mode (no downstream)" do
    let(:app) do
      described_class.set :environment, :test
      described_class.new
    end

    before do
      Class.new(Weft::Page) do
        def self.name = "StandalonePage"
        self.page_path = "/standalone"

        def build(attributes = {})
          super
          div { text_node "standalone-page-content" }
        end
      end
    end

    it "serves an auto-routed component" do
      get "/_components/stat_card", status: "shipped", value: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("shipped")
    end

    it "serves a registered page" do
      get "/standalone"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("standalone-page-content")
    end

    it "returns 404 for unmatched paths (no downstream to fall through to)" do
      get "/nothing-here"

      expect(last_response.status).to eq(404)
    end

    it "renders Weft::Defaults::NotFoundPage for routing misses (full document by default)" do
      get "/nothing-here"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to start_with("<!DOCTYPE html>")
      expect(last_response.body).to include("Not found")
      expect(last_response.body).to include("/nothing-here")
    end

    it "renders only the body fragment for htmx routing-miss requests" do
      get "/nothing-here", {}, "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(404)
      expect(last_response.body).not_to include("<!DOCTYPE")
      expect(last_response.body).not_to include("<html")
      expect(last_response.body).to include("Not found")
    end

    it "renders Weft::Defaults::ErrorPage when a page render itself fails (B1, full doc)" do
      Class.new(Weft::Page) do
        def self.name = "BlowupPage"
        self.page_path = "/blowup"

        def build(_params = {})
          super
          raise "page broke"
        end
      end

      get "/blowup"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to start_with("<!DOCTYPE html>")
      expect(last_response.body).to include("Something went wrong")
      expect(last_response.body).to include("page broke")
    end

    describe "htmx_errors knob" do
      around do |example|
        original = Weft.configuration.htmx_errors
        example.run
        Weft.configuration.htmx_errors = original
      end

      it "emits HX-Redirect to the error_page when :redirect, htmx, and gem-default catches the failure (D1)" do
        Weft.configuration.htmx_errors = :redirect

        Class.new(Weft::Component) do
          def self.name = "RedirectFail"
          param :id

          def build(attributes = {})
            super
            raise "boom"
          end
        end

        get "/_components/redirect_fail", { id: "1" }, "HTTP_HX_REQUEST" => "true"

        expect(last_response.status).to eq(204)
        expect(last_response.headers["HX-Redirect"]).to start_with(Weft::Defaults::ErrorPage.page_path)
      end

      it "does not redirect on routing misses (D3) — still renders the NotFoundPage fragment" do
        Weft.configuration.htmx_errors = :redirect

        get "/nothing-here", {}, "HTTP_HX_REQUEST" => "true"

        expect(last_response.status).to eq(404)
        expect(last_response.headers).not_to have_key("HX-Redirect")
        expect(last_response.body).to include("Not found")
      end

      it "does not redirect when the user declared an explicit recovers target (D2)" do # rubocop:disable RSpec/ExampleLength
        Weft.configuration.htmx_errors = :redirect

        Class.new(Weft::Component) do
          def self.name = "ExplicitRecover"
          param :id
          param :error_message
          recovers(from: StandardError) { |_params, err| { error_message: err.message } }
          def build(attributes = {})
            super
            raise "user-handled" unless params.error_message

            div(class: "explicit") { text_node params.error_message }
          end
        end

        get "/_components/explicit_recover", { id: "1" }, "HTTP_HX_REQUEST" => "true"

        expect(last_response.status).to eq(500)
        expect(last_response.headers).not_to have_key("HX-Redirect")
        expect(last_response.body).to include("explicit")
      end

      it "does not redirect on traditional (non-htmx) requests even when :redirect is set" do
        Weft.configuration.htmx_errors = :redirect

        Class.new(Weft::Component) do
          def self.name = "TradFail"
          param :id

          def build(attributes = {})
            super
            raise "boom"
          end
        end

        get "/_components/trad_fail", id: "1"

        expect(last_response.status).to eq(500)
        expect(last_response.headers).not_to have_key("HX-Redirect")
        expect(last_response.body).to include("Something went wrong")
      end
    end

    it "renders the body fragment when a page render fails under htmx" do
      Class.new(Weft::Page) do
        def self.name = "BlowupPageHtmx"
        self.page_path = "/blowup-htmx"

        def build(_params = {})
          super
          raise "page broke"
        end
      end

      get "/blowup-htmx", {}, "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(500)
      expect(last_response.body).not_to include("<!DOCTYPE")
      expect(last_response.body).to include("Something went wrong")
      expect(last_response.body).to include("page broke")
    end
  end

  describe "static assets serving" do
    require "tmpdir"
    require "fileutils"

    # Each test uses a unique URL prefix so the persisted before-filters
    # don't collide across tests. apply_static_assets! is idempotent per
    # root, so re-running configure with the same root in the same process
    # is also safe.
    let(:tmpdir) { Dir.mktmpdir("weft-static-spec-") }
    let(:url_prefix) { "/static-spec-#{rand(1_000_000)}" }

    around do |example|
      original_config = Weft.configuration
      original_mounted = Weft.instance_variable_get(:@mounted_static_bundles)
      Weft.instance_variable_set(:@configuration, Weft::Configuration.new)
      Weft.instance_variable_set(:@mounted_static_bundles, nil)
      example.run
    ensure
      Weft.instance_variable_set(:@configuration, original_config)
      Weft.instance_variable_set(:@mounted_static_bundles, original_mounted)
      FileUtils.rm_rf(tmpdir)
    end

    def configure_static_assets(root: url_prefix, from: tmpdir)
      Weft.configure { |c| c.static_assets root: root, from: from }
    end

    it "serves a real file under the configured root" do
      File.write(File.join(tmpdir, "app.css"), "body { color: red; }")
      configure_static_assets

      get "#{url_prefix}/app.css"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("body { color: red; }")
      expect(last_response.content_type).to include("text/css")
    end

    it "serves nested files" do
      FileUtils.mkdir_p(File.join(tmpdir, "css"))
      File.write(File.join(tmpdir, "css", "app.css"), "/* nested */")
      configure_static_assets

      get "#{url_prefix}/css/app.css"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("/* nested */")
    end

    it "returns 404 for a missing file" do
      configure_static_assets

      get "#{url_prefix}/missing.css"

      expect(last_response.status).to eq(404)
    end

    it "does not serve files outside the configured root via URL traversal" do
      # Rack normalizes /prefix/../foo to /foo before route dispatch, so the
      # static handler's before-filter pattern doesn't match a traversal URL
      # at all — the request never reaches send_file. (The expand_path
      # containment check inside the handler is belt-and-suspenders for any
      # path that does manage to arrive with a `..`-bearing splat.)
      outside_name = "secret-#{rand(1_000_000)}.txt"
      outside_path = File.join(File.expand_path("..", tmpdir), outside_name)
      File.write(outside_path, "leak")
      File.write(File.join(tmpdir, "app.css"), "ok")
      configure_static_assets

      get "#{url_prefix}/../#{outside_name}"

      expect(last_response.body).not_to eq("leak")
    ensure
      FileUtils.rm_f(outside_path) if outside_path
    end

    it "returns 404 for a directory request" do
      FileUtils.mkdir_p(File.join(tmpdir, "css"))
      configure_static_assets

      get "#{url_prefix}/css"

      expect(last_response.status).to eq(404)
    end

    it "leaves unrelated paths alone" do
      File.write(File.join(tmpdir, "app.css"), "x")
      configure_static_assets

      get "/some/other/route"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("downstream")
    end

    it "supports multiple distinct bundles in one configure" do
      Dir.mktmpdir("weft-static-spec-b-") do |other|
        File.write(File.join(tmpdir, "a.css"), "first")
        File.write(File.join(other, "b.css"), "second")
        other_prefix = "/static-spec-b-#{rand(1_000_000)}"
        Weft.configure do |c|
          c.static_assets name: :app,    root: url_prefix,   from: tmpdir
          c.static_assets name: :vendor, root: other_prefix, from: other
        end

        get "#{url_prefix}/a.css"
        expect(last_response.body).to eq("first")

        get "#{other_prefix}/b.css"
        expect(last_response.body).to eq("second")
      end
    end

    it "is idempotent across repeated configure/apply calls" do
      File.write(File.join(tmpdir, "app.css"), "v1")
      configure_static_assets
      Weft.send(:apply_static_assets!)
      Weft.send(:apply_static_assets!)

      get "#{url_prefix}/app.css"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("v1")
    end
  end
end
