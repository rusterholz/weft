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
      identifies_by :status
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

  # Stands in for Sinatra's Stream in direct-drive streaming specs: collects
  # frames, records the explicit close that stream_component must issue on
  # final exits (with :keep_open, merely returning from the block does not end
  # the response — observed live as the loop re-invoking and the countdown
  # restarting).
  def frame_sink
    Class.new(Array) do
      attr_reader :closed

      def close = @closed = true
    end.new
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
        identifies_by :order_id

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

  describe "one universe per request" do
    let!(:badge_class) do
      Class.new(Weft::Component) do
        def self.name = "AccountBadge"
        param :corporate_account_id, type: :string

        def build(attributes = {})
          super
          span { text_node "badge-#{params.corporate_account_id}" }
        end
      end
    end

    it "keeps the request's wire reaching nested components across the action border" do
      badge = badge_class
      Class.new(Weft::Component) do
        def self.name = "DraftPanel"
        param :order_id, type: :string
        performs(:touch) { nil }

        define_method(:build) do |attributes = {}|
          super(attributes)
          insert_tag(badge)
        end
      end

      post "/_components/draft_panel/touch", order_id: "o-1", corporate_account_id: "acct-9"

      expect(last_response.body).to include("badge-acct-9")
    end

    it "keeps the request's wire reaching nested components across a transfer" do # rubocop:disable RSpec/ExampleLength
      badge = badge_class
      submitted = Class.new(Weft::Component) do
        def self.name = "SubmittedPanel"
        param :order_id, type: :string

        define_method(:build) do |attributes = {}|
          super(attributes)
          div { text_node "submitted-#{params.order_id}" }
          insert_tag(badge)
        end
      end
      Class.new(Weft::Component) do
        def self.name = "DraftFormPanel"
        param :order_id, type: :string
        transfers(:submit, to: submitted) { |_p| nil }
      end

      post "/_components/draft_form_panel/submit", order_id: "o-2", corporate_account_id: "acct-3"

      expect(last_response.body).to include("submitted-o-2")
      expect(last_response.body).to include("badge-acct-3")
    end

    it "lets a callable delta override the wire for nested components" do # rubocop:disable RSpec/ExampleLength
      pager = Class.new(Weft::Component) do
        def self.name = "InnerPager"
        param :page, type: :integer

        def build(attributes = {})
          super
          span { text_node "page-#{params.page}" }
        end
      end
      Class.new(Weft::Component) do
        def self.name = "FilterPanel"
        param :page, type: :integer
        performs(:reset) { |_p| { page: 1 } }

        define_method(:build) do |attributes = {}|
          super(attributes)
          insert_tag(pager)
        end
      end

      post "/_components/filter_panel/reset", page: "5"

      expect(last_response.body).to include("page-1")
      expect(last_response.body).not_to include("page-5")
    end

    # A default is the fallback of whoever declared it, consulted when a read
    # finds nothing — never a value the declarer hands downstream. So it
    # survives the hand-off even though the target inherits everything else
    # the request composed.
    it "keeps a transfer target's own defaults sovereign over the declarer's" do
      target = Class.new(Weft::Component) do
        def self.name = "OpenModeCard"
        param :view, type: :string, default: "open"

        def build(attributes = {})
          super
          div { text_node "view-#{params.view}" }
        end
      end
      Class.new(Weft::Component) do
        def self.name = "AllModePanel"
        param :view, type: :string, default: "all"
        transfers(:show, to: target)
      end

      post "/_components/all_mode_panel/show"

      expect(last_response.body).to include("view-open")
    end

    it "keeps a nested child's own default sovereign over its parent's" do # rubocop:disable RSpec/ExampleLength
      inner = Class.new(Weft::Component) do
        def self.name = "InnerViewCard"
        param :view, type: :string, default: "open"

        def build(attributes = {})
          super
          div { text_node "child-#{params.view}" }
        end
      end
      Class.new(Weft::Component) do
        def self.name = "OuterViewPanel"
        param :view, type: :string, default: "all"

        define_method(:build) do |attributes = {}|
          super(attributes)
          div { text_node "parent-#{params.view}" }
          insert_tag(inner)
        end
      end

      get "/_components/outer_view_panel"

      expect(last_response.body).to include("parent-all")
      expect(last_response.body).to include("child-open")
    end

    it "still lets a declarer's derived value cross the hand-off" do
      target = Class.new(Weft::Component) do
        def self.name = "InheritedOrderCard"

        def build(attributes = {})
          super
          div { text_node "card-#{params.order}" }
        end
      end
      Class.new(Weft::Component) do
        def self.name = "OrderHandOffPanel"
        param :order_id, type: :string
        derives(:order) { |p| "ORDER(#{p.order_id})" }
        transfers(:show, to: target) { |params| params.order and nil }
      end

      post "/_components/order_hand_off_panel/show", order_id: "o-5"

      expect(last_response.body).to include("card-ORDER(o-5)")
    end

    it "pre-empts the target's derivation with a rich delta value" do # rubocop:disable RSpec/ExampleLength
      order = Struct.new(:id).new("o-77")
      target = Class.new(Weft::Component) do
        def self.name = "OrderSummaryCard"
        derives(:order) { |_p| raise "derivation must not run" }

        def build(attributes = {})
          super
          div { text_node "summary-#{params.order.id}" }
        end
      end
      Class.new(Weft::Component) do
        def self.name = "OrderPickerPanel"
        param :order_id, type: :string
        transfers(:pick, to: target) { |_p| { order: order } }
      end

      post "/_components/order_picker_panel/pick", order_id: "o-77"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("summary-o-77")
    end

    it "keeps the request's wire reaching nested components through a recovery render" do # rubocop:disable RSpec/ExampleLength
      badge = badge_class
      Class.new(Weft::Component) do
        def self.name = "SubmittableDraftPanel"
        param :order_id, type: :string
        performs(:submit) { |_p| raise Weft::Unprocessable, "invalid" }
        recovers from: Weft::Unprocessable

        define_method(:build) do |attributes = {}|
          super(attributes)
          div { text_node "draft-#{params.order_id}" }
          insert_tag(badge)
        end
      end

      post "/_components/submittable_draft_panel/submit", order_id: "o-4", corporate_account_id: "acct-5"

      expect(last_response.status).to eq(422)
      expect(last_response.body).to include("draft-o-4")
      expect(last_response.body).to include("badge-acct-5")
    end
  end

  describe "the bag a verb block sees" do
    it "hands a callable its class's derivations" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "DerivingTouchPanel"
        param :order_id, type: :string
        derives(:order) { |p| "ORDER(#{p.order_id})" }
        performs(:touch) { |params| seen << params.order and nil }
      end

      post "/_components/deriving_touch_panel/touch", order_id: "o-1"

      expect(seen).to eq(["ORDER(o-1)"])
    end

    it "hands a callable its class's defined values" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "DefiningTouchPanel"
        defines label: "Drivers"
        performs(:touch) { |params| seen << params.label and nil }
      end

      post "/_components/defining_touch_panel/touch"

      expect(seen).to eq(["Drivers"])
    end

    it "never runs a derivation the callable leaves unread" do
      ran = []
      Class.new(Weft::Component) do
        def self.name = "LazyTouchPanel"
        param :order_id, type: :string
        derives(:untouched) { |_p| ran << :ran }
        performs(:touch) { |_params| nil }
      end

      post "/_components/lazy_touch_panel/touch", order_id: "o-2"

      expect(ran).to be_empty
    end

    it "lets a wire value outrank a same-key derivation" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "WireOverDerivePanel"
        param :status, type: :string
        derives(:status) { |_p| "derived" }
        performs(:touch) { |params| seen << params.status and nil }
      end

      post "/_components/wire_over_derive_panel/touch", status: "from-wire"

      expect(seen).to eq(["from-wire"])
    end

    it "prefers a derivation to the same key's declared default" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "DeriveOverDefaultPanel"
        param :label, type: :string, default: "from-default"
        derives(:label) { |_p| "from-derive" }
        performs(:touch) { |params| seen << params.label and nil }
      end

      post "/_components/derive_over_default_panel/touch"

      expect(seen).to eq(["from-derive"])
    end

    it "keeps hand-offs out of a callable's view" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "HandOffTouchPanel"
        param :order_id, type: :string
        receives :handed, default: "given"
        performs(:touch) { |params| seen << params.key?(:handed) and nil }
      end

      post "/_components/hand_off_touch_panel/touch", order_id: "o-3"

      expect(seen).to eq([false])
    end

    it "walks the recovery chain when a derivation raises inside a callable" do
      Class.new(Weft::Component) do
        def self.name = "MissingRecordPanel"
        param :order_id, type: :string
        derives(:order) { |_p| raise Weft::NotFound, "no such order" }
        performs(:touch) { |params| params.order and nil }
      end

      post "/_components/missing_record_panel/touch", order_id: "gone"

      expect(last_response.status).to eq(404)
    end

    it "carries a value the callable forced into the render it precedes" do
      ran = []
      Class.new(Weft::Component) do
        def self.name = "ForcedOncePanel"
        param :order_id, type: :string
        derives(:order) { |p| ran << :ran and "ORDER(#{p.order_id})" }
        performs(:touch) { |params| params.order and nil }

        def build(attributes = {})
          super
          div { text_node params.order }
        end
      end

      post "/_components/forced_once_panel/touch", order_id: "o-9"

      expect(last_response.body).to include("ORDER(o-9)")
      expect(ran.size).to eq(1)
    end
  end

  describe "recovery sees the state the request had composed" do
    it "hands a recovery block the doors build sees" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "DerivingFailurePanel"
        param :order_id, type: :string
        derives(:order) { |p| "ORDER(#{p.order_id})" }
        performs(:touch) { |_params| raise "callable boom" }
        recovers(from: StandardError) { |params, _e| seen << params.order and {} }
      end

      post "/_components/deriving_failure_panel/touch", order_id: "o-6"

      expect(seen).to eq(["ORDER(o-6)"])
    end

    it "hands the recovery chain the callable's overlay when the build is what failed" do
      seen = []
      Class.new(Weft::Component) do
        def self.name = "LateFailurePanel"
        param :order_id, type: :string
        performs(:touch) { |_params| { note: "from-callable" } }
        recovers(from: StandardError) { |params, _e| seen << params.note and {} }

        def build(attributes = {})
          super
          raise "build boom"
        end
      end

      post "/_components/late_failure_panel/touch", order_id: "o-7"

      expect(seen).to eq(["from-callable"])
    end

    it "walks the rendering component's chain when a transfer's build fails" do # rubocop:disable RSpec/ExampleLength
      recovery = Class.new(Weft::Component) do
        def self.name = "TargetsOwnRecovery"

        def build(attributes = {})
          super
          div { text_node "target-recovery" }
        end
      end
      target = Class.new(Weft::Component) do
        def self.name = "FailingTransferTarget"
        recovers from: StandardError, with: recovery

        def build(attributes = {})
          super
          raise "target boom"
        end
      end
      Class.new(Weft::Component) do
        def self.name = "HandingOffPanel"
        recovers from: StandardError, with: Weft::Defaults::NotFoundComponent
        transfers(:go, to: target)
      end

      post "/_components/handing_off_panel/go"

      expect(last_response.body).to include("target-recovery")
    end

    it "hands a failing companion's recovery block the state its own build saw" do # rubocop:disable RSpec/ExampleLength
      seen = []
      companion = Class.new(Weft::Component) do
        def self.name = "StatefulFlakyCompanion"
        param :slot, type: :string
        recovers(from: StandardError) { |params, _e| seen << params.note and {} }

        def build(attributes = {})
          super
          raise "companion boom"
        end
      end
      Class.new(Weft::Component) do
        def self.name = "CompanionStateHost"
        performs(:touch) { nil }
        brings(companion, on: :touch) { |_p| { note: "from-brings" } }
      end

      post "/_components/companion_state_host/touch", slot: "a"

      expect(seen).to eq(["from-brings"])
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

  describe "class-level announcements" do
    let!(:triggering_class) do # rubocop:disable RSpec/LetSetup
      Class.new(Weft::Component) do
        def self.name = "TriggerTest"
        param :id
        announces "item-updated"
        performs(:save) { nil }
      end
    end

    it "sets HX-Trigger header on action responses" do
      post "/_components/trigger_test/save", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["HX-Trigger"]).to eq("item-updated")
    end

    it "supports multiple announcements" do
      Class.new(Weft::Component) do
        def self.name = "MultiTrigger"
        param :id
        announces "event-a"
        announces "event-b"
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

    context "with an on: filter" do
      let!(:filtered_class) do # rubocop:disable RSpec/LetSetup
        Class.new(Weft::Component) do
          def self.name = "FilteredTrigger"
          param :id
          announces "advanced", on: :advance
          announces "always-fires"
          performs(:advance) { nil }
          performs(:touch) { nil }
        end
      end

      it "fires a filtered event on the action it names" do
        post "/_components/filtered_trigger/advance", id: "1"

        expect(last_response.headers["HX-Trigger"]).to include("advanced")
      end

      it "withholds a filtered event from the component's other actions" do
        post "/_components/filtered_trigger/touch", id: "1"

        expect(last_response.headers["HX-Trigger"]).not_to include("advanced")
      end

      it "keeps an unfiltered event firing on every action" do
        post "/_components/filtered_trigger/touch", id: "1"

        expect(last_response.headers["HX-Trigger"]).to eq("always-fires")
      end

      it "fires a filtered event on any action its array names" do
        Class.new(Weft::Component) do
          def self.name = "ArrayTrigger"
          param :id
          announces "moved", on: %i[advance retreat]
          performs(:advance) { nil }
          performs(:retreat) { nil }
        end

        post "/_components/array_trigger/advance", id: "1"
        expect(last_response.headers["HX-Trigger"]).to eq("moved")

        post "/_components/array_trigger/retreat", id: "1"
        expect(last_response.headers["HX-Trigger"]).to eq("moved")
      end

      it "fires a filtered event on the transfers action it names" do
        target = Class.new(Weft::Component) do
          def self.name = "TriggerArrival"
          param :id
        end
        declarer = Class.new(Weft::Component) do
          def self.name = "TriggerDeparture"
          param :id
          announces "handed-over", on: :hand_off
        end
        declarer.transfers(:hand_off, to: target)

        post "/_components/trigger_departure/hand_off", id: "1"

        expect(last_response.headers["HX-Trigger"]).to eq("handed-over")
      end
    end
  end

  describe "error handling" do
    let!(:failing_class) do
      Class.new(Weft::Component) do
        def self.name = "FailingCard"
        param :id
        identifies_by :id

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

    it "stamps the failing component's DOM id onto the recovery fragment" do
      get "/_components/failing_card", id: "1"
      expect(last_response.body).to include('id="failing-card-1"')
    end

    # The stamp is the Router's, not an opt-in: a recovery target stands in the
    # failing component's place, and a swap addressed anywhere else lands
    # somewhere else. Nothing here declares an identity param.
    it "stamps it onto an unrelated recovery target too" do
      stand_in = Class.new(Weft::Component) do
        def self.name = "StandInCard"
        abstract!

        def build(attributes = {})
          super
          span "stood in"
        end
      end
      failing_class.recovers from: StandardError, with: stand_in

      get "/_components/failing_card", id: "1"

      expect(last_response.body).to include("stood in")
      expect(last_response.body).to include('id="failing-card-1"')
    end

    # Identity can raise on a re-render even though the first render was fine.
    # There is no recovering the id it would have had, so the fragment gets a
    # unique throwaway: it lands nowhere rather than displacing something else.
    it "falls back to a unique unresolved id when identity itself raises" do
      unstable = Class.new(Weft::Component) do
        def self.name = "UnstableId"
        param :id

        def build(attributes = {})
          super
          raise "build broke"
        end

        def weft_dom_id = raise("identity broke")
      end
      expect(unstable).to be_routable

      get "/_components/unstable_id", id: "1"

      expect(last_response.body).to match(/id="unstable-id-unresolved-[0-9a-f]{8}"/)
    end

    # A throwaway id is not an identity — asking identity for slots it cannot
    # fill would invent blank ones, doubling the separator and warning about a
    # collision risk that the throwaway suffix has already ruled out.
    it "builds the unresolved id from the stem alone, not from empty slots" do
      allow(Weft.logger).to receive(:warn)
      unstable = Class.new(Weft::Component) do
        def self.name = "UnstableKeyed"
        param :order_id
        identifies_by :order_id

        def build(attributes = {})
          super
          raise "build broke"
        end

        def weft_dom_id = raise("identity broke")
      end
      expect(unstable).to be_routable

      get "/_components/unstable_keyed", order_id: "1"

      expect(last_response.body).to match(/id="unstable-keyed-unresolved-[0-9a-f]{8}"/)
      expect(Weft.logger).not_to have_received(:warn).with(/rendered blank/)
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

    let(:patient_class) do
      Class.new(Weft::Component) do
        def self.name = "PatientPushCard"
        pushes every: 5, immediate: false
      end
    end

    it "pushes the first frame immediately, then sleeps before subsequent frames" do
      router = described_class.new!(downstream_app)
      order = []
      allow(router).to receive(:content_type)
      allow(router).to receive(:headers)
      allow(router).to receive(:stream).and_yield(frame_sink)
      allow(router).to receive(:sleep) { order << :sleep }
      allow(router).to receive(:push_component_event) do
        order << :push
        raise IOError if order.count(:push) >= 2
      end

      router.send(:stream_component, pushing_class)

      expect(order).to eq(%i[push sleep push])
    end

    it "sleeps before the first frame when the component declares immediate: false" do
      router = described_class.new!(downstream_app)
      order = []
      allow(router).to receive(:content_type)
      allow(router).to receive(:headers)
      allow(router).to receive(:stream).and_yield(frame_sink)
      allow(router).to receive(:sleep) { order << :sleep }
      allow(router).to receive(:push_component_event) do
        order << :push
        raise IOError if order.count(:push) >= 2
      end

      router.send(:stream_component, patient_class)

      expect(order).to eq(%i[sleep push sleep push])
    end
  end

  describe "stream_component failure handling" do
    # Same direct-drive harness as above; failing builds exercise the recovers
    # routing, the attempts countdown, and the sse-close shut-off.
    let(:router) { described_class.new!(downstream_app) }

    let(:notice_card_class) do
      Class.new(Weft::Component) do
        def self.name = "StreamNoticeCard"

        def build(attributes = {})
          super
          span "temporarily unavailable"
        end
      end
    end

    let(:countdown_card_class) do
      Class.new(Weft::Component) do
        def self.name = "CountdownCard"
        param :attempts_remaining

        def build(attributes = {})
          super
          if params.attempts_remaining
            span "remaining-#{params.attempts_remaining}"
          else
            span "http-recovery"
          end
        end
      end
    end
    let(:flapping_class) do
      Class.new(Weft::Component) do
        def self.name = "FlappingCard"

        class << self
          attr_accessor :calls
        end
        @calls = 0
        pushes every: 5, attempts: 2

        def build(attributes = {})
          super
          self.class.calls += 1
          raise "boom" unless self.class.calls == 2

          span "back to normal"
        end
      end
    end

    before do
      allow(router).to receive(:content_type)
      allow(router).to receive(:headers)
      allow(router).to receive_messages(filtered_params: {},
                                        request: Struct.new(:path).new("/stream-test"))
      allow(Weft.logger).to receive(:error)
      # Runaway guard: a regression back to log-and-continue-forever plus a
      # no-op sleep stub would spin the loop unboundedly — bail out via the
      # connection-death path after a bounded number of cycles instead.
      sleeps = 0
      allow(router).to receive(:sleep) do
        sleeps += 1
        raise IOError if sleeps > 10
      end
    end

    def failing_class(name = "FlakyCard", **push_kwargs)
      Class.new(Weft::Component) do
        define_singleton_method(:name) { name }
        pushes(every: 5, **push_kwargs)

        def build(attributes = {})
          super
          raise "boom"
        end
      end
    end

    it "routes a failing push through the recovers chain, shipping content-only under the original event id" do
      component_class = failing_class(attempts: 1)
      component_class.recovers(from: StandardError, with: notice_card_class)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out.length).to eq(2)
      expect(out[0]).to include("event: flaky-card")
      expect(out[0]).to include("temporarily unavailable")
      expect(out[0]).not_to include("stream-notice-card") # like-for-like: no recovery wrapper
      expect(out[1]).to eq("event: weft:close\ndata: \n\n") # bare data line so EventSource dispatches
    end

    it "closes after the declared attempts budget of consecutive failures, and says so in the log" do
      component_class = failing_class(attempts: 2)
      component_class.recovers(from: StandardError, with: notice_card_class)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out.length).to eq(3)
      expect(out[0]).to include("event: flaky-card")
      expect(out[1]).to include("event: flaky-card")
      expect(out[2]).to include("event: weft:close")
      expect(out.closed).to be(true)
      expect(Weft.logger).to have_received(:error).
        with(/closed after 2 consecutive failed pushes/)
    end

    # A companion riding a push frame is still only a companion: its failure
    # says nothing about the stream's health, so it must not spend the
    # attempts budget or close the connection.
    it "contains a failing companion inside the frame, leaving the stream and its budget alone" do # rubocop:disable RSpec/ExampleLength
      boom = Class.new(Weft::Component) do
        def self.name = "PushBoomCompanion"

        def build(attributes = {})
          super
          raise "companion exploded"
        end
      end
      healthy = Class.new(Weft::Component) do
        def self.name = "HealthyPushCard"
        pushes every: 5, attempts: 1

        def build(attributes = {})
          super
          span "live data"
        end
      end
      healthy.brings(boom)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, healthy)

      expect(out.first).to include("live data")
      expect(out.first).to include("Something went wrong")
      expect(out.first).to include('hx-swap-oob="true"')
      expect(out.first).to include('id="push-boom-companion"')
      expect(out).to all(satisfy { |frame| !frame.include?("weft:close") })
    end

    it "keeps throttling failing pushes on the cadence interval" do
      component_class = failing_class(attempts: 2)
      component_class.recovers(from: StandardError, with: notice_card_class)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)
      allow(router).to receive(:sleep) do
        out << :sleep
        raise IOError if out.count(:sleep) > 10 # runaway guard, as in the before block
      end

      router.send(:stream_component, component_class)

      expect(out.length).to eq(4)
      expect(out[1]).to eq(:sleep) # between the two failure cycles; close follows in-cycle
    end

    it "resets the failure count on a successful push" do
      component_class = flapping_class
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      # fail, success, fail, fail: the mid-stream success must restore the
      # full budget, or the third cycle would already have closed the stream.
      expect(out.length).to eq(5)
      expect(out[1]).to include("back to normal")
      expect(out[4]).to include("event: weft:close")
    end

    it "ships no recovery frame when the chain yields only Page targets, but still closes" do
      original = Weft.configuration.error_component
      Weft.configuration.error_component = Class.new(Weft::Page) { def self.name = "StreamPageOnly" }
      component_class = failing_class(attempts: 1)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out.length).to eq(1)
      expect(out[0]).to include("event: weft:close")
      expect(Weft.logger).to have_received(:error).with(/SSE push error/)
    ensure
      Weft.configuration.error_component = original
    end

    it "logs and skips the frame when the recovery render itself raises, still counting the failure" do
      broken_recovery = Class.new(Weft::Component) do
        def self.name = "BrokenRecoveryCard"

        def build(attributes = {})
          super
          raise "recovery is broken too"
        end
      end
      component_class = failing_class(attempts: 1)
      component_class.recovers(from: StandardError, with: broken_recovery)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out.length).to eq(1)
      expect(out[0]).to include("event: weft:close")
      expect(Weft.logger).to have_received(:error).with(/Push recovery render failed/)
    end

    it "falls back to the configured push_attempts when the declaration names none" do
      original = Weft.configuration.push_attempts
      Weft.configuration.push_attempts = 1
      component_class = failing_class
      component_class.recovers(from: StandardError, with: notice_card_class)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out.length).to eq(2)
      expect(out[1]).to include("event: weft:close")
    ensure
      Weft.configuration.push_attempts = original
    end

    it "injects the attempts_remaining countdown into recovery targets that declare it" do
      component_class = failing_class(attempts: 2)
      component_class.recovers(from: StandardError, with: countdown_card_class)
      out = frame_sink
      allow(router).to receive(:stream).and_yield(out)

      router.send(:stream_component, component_class)

      expect(out[0]).to include("remaining-1")
      expect(out[1]).to include("remaining-0")
    end

    it "leaves attempts_remaining unset on HTTP-path recoveries" do
      component_class = failing_class("HttpFlakyCard")
      component_class.recovers(from: StandardError, with: countdown_card_class)

      get "/_components/http_flaky_card"

      expect(last_response.body).to include("http-recovery")
    end

    it "tears down cleanly when the client vanishes mid-recovery-write" do
      component_class = failing_class(attempts: 3)
      component_class.recovers(from: StandardError, with: notice_card_class)
      dead_connection = Class.new do
        attr_reader :closed

        # Expanded defs: CodeQL's Ruby extractor chokes on the endless forms.
        def <<(_frame)
          raise Errno::EPIPE
        end

        def close
          @closed = true
        end
      end.new
      allow(router).to receive(:stream).and_yield(dead_connection)

      expect { router.send(:stream_component, component_class) }.not_to raise_error
      expect(dead_connection.closed).to be(true)
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

  describe "build_component_with_wire" do
    it "builds a component that resolves its params from the wire source" do
      router = described_class.new!(downstream_app)
      component = router.send(:build_component_with_wire, stat_card_class, { status: "shipped", value: 10 })

      expect(component).to be_a(Weft::Component)
      expect(component.weft_dom_id).to eq("stat-card-shipped")
      expect(component.content).to include("shipped")
      expect(component.to_s).to include('id="stat-card-shipped"')
    end

    it "returns children-only HTML via content (for SSE innerHTML swap)" do
      router = described_class.new!(downstream_app)
      component = router.send(:build_component_with_wire, stat_card_class, { status: "shipped", value: 10 })

      # content returns children only — no wrapper div
      expect(component.content).not_to include('id="stat-card-shipped"')
      expect(component.content).to include("shipped")
      expect(component.content).to include("10")

      # to_s returns the full component including wrapper
      expect(component.to_s).to include('id="stat-card-shipped"')
    end
  end

  describe "OOB companions in action responses" do
    let!(:included_class) do
      Class.new(Weft::Component) do
        def self.name = "IncludedHeader"
        param :order_id
        identifies_by :order_id

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

    before { including_class.brings(included_class) }

    it "appends OOB-swapped component to action responses" do
      post "/_components/including_card/refresh_all", order_id: "42"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include('hx-swap-oob="true"')
      expect(last_response.body).to include("header-for-42")
    end

    it "respects on: filter — rides only for matching actions" do
      filtered_class = included_class
      source = Class.new(Weft::Component) do
        def self.name = "FilteredInc"
        param :order_id
        performs(:advance) { nil }
        performs(:noop) { nil }
      end
      source.brings(filtered_class, on: :advance)

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
      source.brings(mapped_class) { |params| { order_id: params[:id] } }

      post "/_components/mapped_inc/go", id: "99"

      expect(last_response.body).to include("header-for-99")
      expect(last_response.body).to include('hx-swap-oob="true"')
    end

    it "passes callable-returned keys through the accumulated bag to companion blocks" do
      sink = included_class
      source = Class.new(Weft::Component) do
        def self.name = "BagSource"
        param :order_id
        # :note is not declared — it only exists on the accumulated bag because
        # the callable returned it. The companion block must still see it.
        performs(:go) { |_params| { note: "from-callable" } }
      end
      source.brings(sink) { |params| { order_id: params[:note] } }

      post "/_components/bag_source/go", order_id: "1"

      expect(last_response.body).to include("header-for-from-callable")
      expect(last_response.body).to include('hx-swap-oob="true"')
    end
  end

  describe "companion ownership and filters" do
    let!(:companion_class) do
      Class.new(Weft::Component) do
        def self.name = "SideCounter"
        param :order_id

        def build(attributes = {})
          super
          span "side-#{params.order_id}"
        end
      end
    end

    let!(:other_companion_class) do
      Class.new(Weft::Component) do
        def self.name = "OtherCounter"
        param :order_id

        def build(attributes = {})
          super
          span "other-#{params.order_id}"
        end
      end
    end

    it "fires the render target's companions on a transfers response, not the declarer's" do # rubocop:disable RSpec/ExampleLength
      mine = companion_class
      theirs = other_companion_class
      target = Class.new(Weft::Component) do
        def self.name = "ArrivalCard"
        param :order_id
      end
      target.brings(mine)
      declarer = Class.new(Weft::Component) do
        def self.name = "DepartureCard"
        param :order_id
      end
      declarer.brings(theirs)
      declarer.transfers(:hand_over, to: target)

      post "/_components/departure_card/hand_over", order_id: "9"

      expect(last_response.body).to include("side-9")
      expect(last_response.body).not_to include("other-9")
    end

    it "never matches an on: filter against a foreign action name" do # rubocop:disable RSpec/ExampleLength
      mine = companion_class
      target = Class.new(Weft::Component) do
        def self.name = "NamespacedTarget"
        param :order_id
        performs(:submit) { nil }
      end
      target.brings(mine, on: :submit)
      declarer = Class.new(Weft::Component) do
        def self.name = "NamespacedDeclarer"
        param :order_id
      end
      declarer.transfers(:submit, to: target)

      post "/_components/namespaced_declarer/submit", order_id: "3"
      expect(last_response.body).not_to include("side-3")

      post "/_components/namespaced_target/submit", order_id: "3"
      expect(last_response.body).to include("side-3")
    end

    it "fires when: :transferred companions only on transfer arrivals" do # rubocop:disable RSpec/ExampleLength
      mine = companion_class
      target = Class.new(Weft::Component) do
        def self.name = "TransferScopedTarget"
        param :order_id
        performs(:poke) { nil }
      end
      target.brings(mine, when: :transferred)
      declarer = Class.new(Weft::Component) do
        def self.name = "TransferScopedDeclarer"
        param :order_id
      end
      declarer.transfers(:send_over, to: target)

      post "/_components/transfer_scoped_target/poke", order_id: "5"
      expect(last_response.body).not_to include("side-5")

      post "/_components/transfer_scoped_declarer/send_over", order_id: "5"
      expect(last_response.body).to include("side-5")
    end

    it "unions on: and when: filters" do # rubocop:disable RSpec/ExampleLength
      mine = companion_class
      target = Class.new(Weft::Component) do
        def self.name = "UnionTarget"
        param :order_id
        performs(:refresh) { nil }
        performs(:noop) { nil }
      end
      target.brings(mine, on: :refresh, when: :transferred)
      declarer = Class.new(Weft::Component) do
        def self.name = "UnionDeclarer"
        param :order_id
      end
      declarer.transfers(:pass_along, to: target)

      post "/_components/union_target/refresh", order_id: "6"
      expect(last_response.body).to include("side-6")

      post "/_components/union_target/noop", order_id: "6"
      expect(last_response.body).not_to include("side-6")

      post "/_components/union_declarer/pass_along", order_id: "6"
      expect(last_response.body).to include("side-6")
    end

    it "matches any action name in an on: array" do
      mine = companion_class
      source = Class.new(Weft::Component) do
        def self.name = "ArrayFilterCard"
        param :order_id
        performs(:advance) { nil }
        performs(:retreat) { nil }
        performs(:hold) { nil }
      end
      source.brings(mine, on: %i[advance retreat])

      post "/_components/array_filter_card/advance", order_id: "8"
      expect(last_response.body).to include("side-8")

      post "/_components/array_filter_card/retreat", order_id: "8"
      expect(last_response.body).to include("side-8")

      post "/_components/array_filter_card/hold", order_id: "8"
      expect(last_response.body).not_to include("side-8")
    end

    it "renders one fragment when two declarations resolve to the same DOM id" do
      mine = companion_class
      source = Class.new(Weft::Component) do
        def self.name = "DoubleIncluder"
        param :order_id
        performs(:advance) { nil }
      end
      source.brings(mine)
      source.brings(mine, on: :advance)

      post "/_components/double_includer/advance", order_id: "9"

      expect(last_response.body.scan("side-9").size).to eq(1)
    end

    it "fires the declarer's on:-filtered companion on its own transfers action" do
      mine = companion_class
      target = Class.new(Weft::Component) do
        def self.name = "HandoffArrival"
        param :order_id
      end
      declarer = Class.new(Weft::Component) do
        def self.name = "HandoffDeparture"
        param :order_id
      end
      declarer.brings(mine, on: :hand_off)
      declarer.transfers(:hand_off, to: target)

      post "/_components/handoff_departure/hand_off", order_id: "7"

      expect(last_response.body).to include("side-7")
    end

    it "hands the declarer's companion block the declarer's picture, not the target's" do
      mine = companion_class
      target = Class.new(Weft::Component) do
        def self.name = "LabelledArrival"
        param :order_id
        derives(:label) { "target-side" }
      end
      declarer = Class.new(Weft::Component) do
        def self.name = "LabelledDeparture"
        param :order_id
      end
      declarer.brings(mine, on: :hand_off) { |params| { order_id: params[:label] || "declarer-side" } }
      declarer.transfers(:hand_off, to: target)

      post "/_components/labelled_departure/hand_off", order_id: "7"

      expect(last_response.body).to include("side-declarer-side")
    end

    # The deltas differ, so a class-and-delta rule would let both through —
    # but only `note` differs and the id rides `order_id`, so both fragments
    # are aimed at one slot and the rendered component's declaration wins.
    it "gives the rendered component the slot when both sides claim one DOM id" do # rubocop:disable RSpec/ExampleLength
      allow(Weft.logger).to receive(:warn)
      noted = Class.new(Weft::Component) do
        def self.name = "NotedCounter"
        param :order_id
        param :note

        def build(attributes = {})
          super
          span "noted-#{params.note}"
        end
      end
      target = Class.new(Weft::Component) do
        def self.name = "SlotArrival"
        param :order_id
      end
      declarer = Class.new(Weft::Component) do
        def self.name = "SlotDeparture"
        param :order_id
      end
      target.brings(noted, when: :transferred) { { note: "from-target" } }
      declarer.brings(noted, on: :hand_off) { { note: "from-declarer" } }
      declarer.transfers(:hand_off, to: target)

      post "/_components/slot_departure/hand_off", order_id: "7"

      expect(last_response.body).to include("noted-from-target")
      expect(last_response.body).not_to include("noted-from-declarer")
      # Proves the declarer's companion resolved and was turned away, rather
      # than never having fired at all.
      expect(Weft.logger).to have_received(:warn).with(/NotedCounter companion/)
    end

    # The losing declaration is not merely discarded after rendering — it never
    # renders. A component finds its slot taken as it builds, before its own
    # build body runs, which is where the work is.
    it "abandons a losing companion before its build body runs" do # rubocop:disable RSpec/ExampleLength
      allow(Weft.logger).to receive(:warn)
      builds = 0
      counted = Class.new(Weft::Component) do
        def self.name = "CountedCounter"
        param :order_id
        define_method(:build) do |attributes = {}|
          super(attributes)
          builds += 1
        end
      end
      source = Class.new(Weft::Component) do
        def self.name = "TwiceIncluder"
        param :order_id
        performs(:advance) { nil }
      end
      source.brings(counted)
      source.brings(counted, on: :advance)

      post "/_components/twice_includer/advance", order_id: "9"

      expect(builds).to eq(1)
    end

    # The primary is a fragment with a DOM id like any other, and it is the one
    # the response is actually about — a companion aimed at its slot would swap
    # over the very thing that just arrived.
    it "keeps the primary's own slot safe from a companion claiming it" do # rubocop:disable RSpec/ExampleLength
      allow(Weft.logger).to receive(:warn)
      thief = Class.new(Weft::Component) do
        def self.name = "SlotThief"
        param :order_id
        identifies_by :order_id

        # An id override aimed squarely at the primary's slot.
        def weft_dom_id = "host-card-#{params.order_id}"

        def build(attributes = {})
          super
          span "companion-copy"
        end
      end
      source = Class.new(Weft::Component) do
        def self.name = "HostCard"
        param :order_id
        identifies_by :order_id
        performs(:advance) { nil }

        def build(attributes = {})
          super
          span "the-primary"
        end
      end
      source.brings(thief, on: :advance)

      post "/_components/host_card/advance", order_id: "3"

      expect(last_response.body).to include("the-primary")
      expect(last_response.body).not_to include("companion-copy")
      expect(Weft.logger).to have_received(:warn).with(/already claimed by the component this response renders/)
    end

    it "names both declaration sites when two companions claim one DOM id" do
      allow(Weft.logger).to receive(:warn)
      mine = companion_class
      source = Class.new(Weft::Component) do
        def self.name = "CollidingIncluder"
        param :order_id
        performs(:advance) { nil }
      end
      source.brings(mine)
      source.brings(mine, on: :advance)

      post "/_components/colliding_includer/advance", order_id: "9"

      expect(Weft.logger).to have_received(:warn).
        with(/SideCounter companion declared at .+:\d+ was dropped.+already claimed by .+:\d+\./m)
    end

    it "keeps both fragments when two declarations resolve to different DOM ids" do # rubocop:disable RSpec/ExampleLength
      eye = Class.new(Weft::Component) do
        def self.name = "EyeCard"
        param :side
        identifies_by :side

        def build(attributes = {})
          super
          span "eye-#{params.side}"
        end
      end
      face = Class.new(Weft::Component) do
        def self.name = "FaceCard"
        param :order_id
        identifies_by :order_id
        performs(:blink) { nil }
      end
      face.brings(eye, on: :blink) { { side: "right" } }
      face.brings(eye, on: :blink) { { side: "left" } }

      post "/_components/face_card/blink", order_id: "1"

      expect(last_response.body).to include("eye-right")
      expect(last_response.body).to include("eye-left")
    end
  end

  describe "companion render containment" do
    let!(:boom_companion) do
      Class.new(Weft::Component) do
        def self.name = "BoomCompanion"
        param :order_id
        identifies_by :order_id

        def build(attributes = {})
          super
          raise "companion exploded"
        end
      end
    end

    let!(:steady_class) do # rubocop:disable RSpec/LetSetup
      companion = boom_companion
      klass = Class.new(Weft::Component) do
        def self.name = "SteadyCard"
        param :order_id
        performs(:advance) { nil }

        def build(attributes = {})
          super
          span "steady-#{params.order_id}"
        end
      end
      klass.brings(companion, on: :advance)
      klass
    end

    before do
      allow(Weft.logger).to receive(:warn)
      allow(Weft.logger).to receive(:error)
    end

    # The action committed its side effects before the companion ever ran, so
    # reporting the response as a failure is a lie about what happened.
    it "leaves the primary render and its status alone when a companion raises" do
      post "/_components/steady_card/advance", order_id: "7"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("steady-7")
    end

    it "renders the failed companion's own recovery as a companion" do
      post "/_components/steady_card/advance", order_id: "7"

      expect(last_response.body).to include("Something went wrong")
      expect(last_response.body).to include('hx-swap-oob="true"')
    end

    it "addresses the error fragment at the slot the failed companion would have filled" do
      post "/_components/steady_card/advance", order_id: "7"

      expect(last_response.body).to include('id="boom-companion-7"')
    end

    # The delta decides where the companion was headed, so it has to decide
    # where its failure is reported too.
    it "follows an id-bearing delta when placing the error fragment" do
      relocating = Class.new(Weft::Component) do
        def self.name = "RelocatingHost"
        param :order_id
        identifies_by :order_id
        performs(:advance) { nil }
      end
      relocating.brings(boom_companion, on: :advance) { { order_id: "elsewhere" } }

      post "/_components/relocating_host/advance", order_id: "7"

      expect(last_response.body).to include('id="boom-companion-elsewhere"')
      expect(last_response.body).not_to include('id="boom-companion-7"')
    end
  end

  describe "companions as OOB-delivered children" do
    it "inherits the primary's bag, rich derivations included, without re-deriving" do # rubocop:disable RSpec/ExampleLength
      derive_calls = 0
      order = Struct.new(:id, :label).new("o-1", "Crate")
      companion = Class.new(Weft::Component) do
        def self.name = "OrderEcho"

        def build(attributes = {})
          super
          span "echo-#{params[:order].label}"
        end
      end
      primary = Class.new(Weft::Component) do
        def self.name = "OrderKeeper"
        param :order_id
        derives(:order) do |_p|
          derive_calls += 1
          order
        end
        performs(:touch) { nil }

        def build(attributes = {})
          super
          div { text_node "keeper-#{params.order.label}" }
        end
      end
      primary.brings(companion)

      post "/_components/order_keeper/touch", order_id: "o-1"

      expect(last_response.body).to include("keeper-Crate")
      expect(last_response.body).to include("echo-Crate")
      expect(derive_calls).to eq(1)
    end

    it "gives each companion its own delta, invisible to the others" do # rubocop:disable RSpec/ExampleLength
      seen = Class.new(Weft::Component) do
        def self.name = "FooSeer"
        param :foo
        param :bar

        def build(attributes = {})
          super
          span "foo-seer[#{params.foo}|#{params.bar}]"
        end
      end
      other = Class.new(Weft::Component) do
        def self.name = "BarSeer"
        param :foo
        param :bar

        def build(attributes = {})
          super
          span "bar-seer[#{params.foo}|#{params.bar}]"
        end
      end
      primary = Class.new(Weft::Component) do
        def self.name = "DeltaSplitter"
        performs(:go) { nil }
      end
      primary.brings(seen) { |_p| { foo: "1" } }
      primary.brings(other) { |_p| { bar: "2" } }

      post "/_components/delta_splitter/go"

      expect(last_response.body).to include("foo-seer[1|]")
      expect(last_response.body).to include("bar-seer[|2]")
    end

    it "resolves a blockless companion from the request universe, like every other form" do # rubocop:disable RSpec/ExampleLength
      companion = Class.new(Weft::Component) do
        def self.name = "UniverseReader"
        param :corporate_account_id, type: :string

        def build(attributes = {})
          super
          span "reader-#{params.corporate_account_id}"
        end
      end
      primary = Class.new(Weft::Component) do
        def self.name = "NarrowPrimary"
        param :order_id
        performs(:go) { nil }
      end
      primary.brings(companion)

      post "/_components/narrow_primary/go", order_id: "1", corporate_account_id: "acct-2"

      expect(last_response.body).to include("reader-acct-2")
    end

    it "treats a blockless companion exactly like an empty-hash block" do # rubocop:disable RSpec/ExampleLength
      blockless_sink = Class.new(Weft::Component) do
        def self.name = "BlocklessSink"
        param :order_id

        def build(attributes = {})
          super
          span "blockless-#{params.order_id}"
        end
      end
      blockful_sink = Class.new(Weft::Component) do
        def self.name = "BlockfulSink"
        param :order_id

        def build(attributes = {})
          super
          span "blockful-#{params.order_id}"
        end
      end
      primary = Class.new(Weft::Component) do
        def self.name = "EquivalencePrimary"
        param :order_id
        performs(:go) { |_p| { order_id: "overridden" } }
      end
      primary.brings(blockless_sink)
      primary.brings(blockful_sink) { |_p| {} }

      post "/_components/equivalence_primary/go", order_id: "wire"

      expect(last_response.body).to include("blockless-overridden")
      expect(last_response.body).to include("blockful-overridden")
    end
  end

  describe "verb blocks run against a sandbox self, not the component class" do
    # performs/transfers/recovers/brings blocks execute in a fresh
    # Weft::DSL::Sandbox, so `self` reaches no component or class state. A block
    # that reports `self.class.name` names the sandbox — before the flip, a
    # class-body proc's self was the component class, so `self.class` was `Class`.

    it "runs a performs callable in the sandbox" do
      Class.new(Weft::Component) do
        def self.name = "SandboxPerform"
        param :marker, default: "start"
        performs(:probe, method: :get) { |_params| { marker: self.class.name } }

        def build(attributes = {})
          super
          span(class: "marker") { text_node params.marker }
        end
      end

      get "/_components/sandbox_perform/probe"

      expect(last_response.body).to include("Weft::DSL::Sandbox")
    end

    it "runs a recovers block in the sandbox" do
      Class.new(Weft::Component) do
        def self.name = "SandboxRecover"
        param :id
        param :recovered_by
        recovers(from: StandardError) { |_params, _error| { recovered_by: self.class.name } }

        def build(attributes = {})
          super
          raise "trigger" unless params.recovered_by

          span(class: "who") { text_node params.recovered_by }
        end
      end

      get "/_components/sandbox_recover", id: "1"

      expect(last_response.body).to include("Weft::DSL::Sandbox")
    end

    it "runs a brings block in the sandbox" do # rubocop:disable RSpec/ExampleLength
      sink = Class.new(Weft::Component) do
        def self.name = "SandboxIncluded"
        param :label, default: "none"

        def build(attributes = {})
          super
          span(class: "included-label") { text_node params.label }
        end
      end
      source = Class.new(Weft::Component) do
        def self.name = "SandboxIncluding"
        param :id
        performs(:go) { nil }
      end
      source.brings(sink) { |_params| { label: self.class.name } }

      post "/_components/sandbox_including/go", id: "1"

      expect(last_response.body).to include("Weft::DSL::Sandbox")
    end
  end

  describe "delete-swap short-circuit" do
    it "returns an empty success body instead of a dead render" do
      Class.new(Weft::Component) do
        def self.name = "DismissEmpty"
        param :id
        dismisses(:remove) { nil }

        def build(attributes = {})
          super
          span "content htmx would discard"
        end
      end

      delete "/_components/dismiss_empty/remove", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("")
    end

    it "never renders the component after the callable deletes its record" do
      store = { "1" => "a record" }
      Class.new(Weft::Component) do
        def self.name = "DismissDeletes"
        param :id
        dismisses(:destroy) { |p| store.delete(p.id) }

        define_method(:build) do |attributes = {}|
          super(attributes)
          raise "record gone" unless store[params.id]

          span store[params.id]
        end
      end

      delete "/_components/dismiss_deletes/destroy", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("")
      expect(store).to be_empty
    end

    it "sends only OOB include fragments when companions apply" do # rubocop:disable RSpec/ExampleLength
      sink = Class.new(Weft::Component) do
        def self.name = "DismissOobSink"
        param :id

        def build(attributes = {})
          super
          span(class: "sink") { text_node "sibling update" }
        end
      end
      source = Class.new(Weft::Component) do
        def self.name = "DismissOobSource"
        param :id
        dismisses(:remove) { nil }

        def build(attributes = {})
          super
          span(class: "primary") { text_node "primary body" }
        end
      end
      source.brings(sink)

      delete "/_components/dismiss_oob_source/remove", id: "1"

      expect(last_response.body).to include('hx-swap-oob="true"')
      expect(last_response.body).to include("sibling update")
      expect(last_response.body).not_to include("primary body")
    end

    it "applies to performs with swap: :delete, not just the sugar" do
      Class.new(Weft::Component) do
        def self.name = "RawDeleteSwap"
        param :id
        performs(:vanish, swap: :delete) { nil }

        def build(attributes = {})
          super
          span "dead body"
        end
      end

      post "/_components/raw_delete_swap/vanish", id: "1"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("")
    end

    it "still carries HX-Trigger events on the empty response" do
      klass = Class.new(Weft::Component) do
        def self.name = "DismissTriggers"
        param :id
        dismisses(:remove) { nil }
      end
      klass.announces "row-removed"

      delete "/_components/dismiss_triggers/remove", id: "1"

      expect(last_response.headers["HX-Trigger"]).to eq("row-removed")
      expect(last_response.body).to eq("")
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

    it "reports a declared status: override for a non-HTTPError" do
      Class.new(Weft::Component) do
        def self.name = "MappedErrorCard"
        param :id
        param :error_message

        recovers(from: KeyError, status: 404) { |_params, error| { error_message: error.message } }

        def build(attributes = {})
          super
          raise KeyError, "no such thing" unless params.error_message

          div { text_node "recovered: #{params.error_message}" }
        end
      end

      get "/_components/mapped_error_card", id: "1"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("recovered: no such thing")
    end

    it "carries the override into a Page-context recovery and its :status_code param" do # rubocop:disable RSpec/ExampleLength
      target = Class.new(Weft::Page) do
        def self.name = "MappedLostPage"
        self.page_path = "/mapped-lost"
        param :status_code

        def build(attributes = {})
          super
          div(class: "mapped-404") { text_node "code-#{params.status_code}" }
        end
      end
      Class.new(Weft::Page) do
        def self.name = "KeyMissingPage"
        self.page_path = "/key-missing"

        recovers(from: KeyError, with: target, status: 404)

        def build(attributes = {})
          super
          raise KeyError, "gone"
        end
      end

      get "/key-missing"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("code-404")
    end
  end

  # A normally-returned 404 body must leave the building untouched: Sinatra
  # runs error_block!(response.status) after every dispatch, so any error(404)
  # registration would replace custom recovery bodies with the default chain's
  # output. These pin the no-clobber contract for every 404-producing path.
  describe "custom NotFound recoveries" do
    let!(:branded_lost_page) do
      Class.new(Weft::Page) do
        def self.name = "BrandedLostPage"
        self.page_path = "/branded-lost"
        param :request_path

        def build(attributes = {})
          super
          div(class: "branded-404") { text_node "Branded: #{params.request_path}" }
        end
      end
    end

    let!(:missing_record_page) do # rubocop:disable RSpec/LetSetup
      target = branded_lost_page
      Class.new(Weft::Page) do
        def self.name = "MissingRecordPage"
        self.page_path = "/missing-record"

        recovers(from: Weft::NotFound, with: target)

        def build(attributes = {})
          super
          raise Weft::NotFound, "no such record"
        end
      end
    end

    it "honors a Page's own recovers from: Weft::NotFound declaration (traditional, full document)" do
      get "/missing-record"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("branded-404")
    end

    it "honors the declaration for htmx requests (body fragment)" do
      get "/missing-record", {}, "HTTP_HX_REQUEST" => "true"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("branded-404")
      expect(last_response.body).not_to include("<html")
    end

    it "keeps a component's own 404 recovery fragment instead of swapping in a page document" do
      Class.new(Weft::Component) do
        def self.name = "MissingThingCard"
        param :id
        param :error_message

        recovers(from: Weft::NotFound) { |_params, error| { error_message: error.message } }

        def build(attributes = {})
          super
          raise Weft::NotFound, "no such thing" unless params.error_message

          div(class: "custom-404") { text_node "Gone: #{params.error_message}" }
        end
      end

      get "/_components/missing_thing_card", id: "1"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("custom-404")
      expect(last_response.body).not_to include("<html")
    end

    context "when a downstream app answers with its own 404" do
      let(:downstream_app) do
        ->(_env) { [404, { "content-type" => "text/plain" }, ["downstream 404 body"]] }
      end

      it "passes the downstream body through untouched (middleware mode)" do
        get "/not-a-weft-path"

        expect(last_response.status).to eq(404)
        expect(last_response.body).to eq("downstream 404 body")
      end
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

    it "injects :component_tag when the target declares it — the failing component's wrapper tag" do
      Class.new(Weft::Component) do
        def self.name = "InjectsTag"
        param :id
        param :component_tag

        recovers(from: StandardError)

        def tag_name = "tr"

        def build(attributes = {})
          super
          raise "boom" unless params.component_tag

          td(class: "got-tag") { text_node "tag=#{params.component_tag}" }
        end
      end

      get "/_components/injects_tag", id: "1"

      expect(last_response.body).to include("tag=tr")
    end

    it "renders the gem-default error fragment with a failing <tr> component's tag" do
      Class.new(Weft::Component) do
        def self.name = "RowBoom"
        param :id

        def tag_name = "tr"

        def build(attributes = {})
          super
          raise "row exploded"
        end
      end

      get "/_components/row_boom", id: "1"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to match(/\A<tr\b/)
      expect(last_response.body).to include("weft-error")
    end

    it "falls back to a div when the failing component's tag_name needs instance state" do
      Class.new(Weft::Component) do
        def self.name = "StatefulTagBoom"
        param :kind

        def tag_name = (params.kind == "row" ? "tr" : "div")

        def build(attributes = {})
          super
          raise "boom"
        end
      end

      get "/_components/stateful_tag_boom", kind: "row"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to match(/\A<div\b/)
      expect(last_response.body).to include("weft-error")
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
