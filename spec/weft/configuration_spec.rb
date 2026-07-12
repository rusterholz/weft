# frozen_string_literal: true

require "logger"

RSpec.describe Weft::Configuration do
  subject(:config) { described_class.new }

  describe "#log_level" do
    it "defaults to :info" do
      expect(config.log_level).to eq(:info)
    end

    it "accepts a known level symbol" do
      config.log_level = :debug
      expect(config.log_level).to eq(:debug)
    end

    it "rejects unknown levels" do
      expect { config.log_level = :loud }.to raise_error(ArgumentError, /log_level/)
    end

    it "resolves the symbol to a Logger severity constant" do
      config.log_level = :warn
      expect(config.resolved_log_level).to eq(Logger::WARN)
    end
  end

  describe "#component_path" do
    it "defaults to a proc that derives path from class name under /_components/" do
      expect(config.component_path).to be_a(Proc)
    end

    it "derives unnamespaced class paths" do
      stub_const("StatCard", Class.new)
      expect(config.component_path.call(StatCard)).to eq("/_components/stat_card")
    end

    it "derives namespaced class paths from module nesting" do
      stub_const("Oms::OrderHeader", Class.new)
      expect(config.component_path.call(Oms::OrderHeader)).to eq("/_components/oms/order_header")
    end

    it "handles deeply nested namespaces" do
      stub_const("Oms::Fulfillment::ShipmentCard", Class.new)
      path = config.component_path.call(Oms::Fulfillment::ShipmentCard)
      expect(path).to eq("/_components/oms/fulfillment/shipment_card")
    end

    it "strips a trailing 'Component' suffix from the class name" do
      stub_const("Oms::OrderHeaderComponent", Class.new)
      expect(config.component_path.call(Oms::OrderHeaderComponent)).to eq("/_components/oms/order_header")
    end
  end

  describe "#component_path=" do
    it "accepts a custom proc" do
      custom = ->(klass) { "/custom/#{klass.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}" }
      config.component_path = custom

      stub_const("Oms::OrderHeader", Class.new)
      expect(config.component_path.call(Oms::OrderHeader)).to eq("/custom/order_header")
    end

    it "rejects non-proc values" do
      expect { config.component_path = "/static/path" }.to raise_error(ArgumentError, /must be a Proc/)
    end
  end

  describe "#auto_reload" do
    it "defaults to false" do
      expect(config.auto_reload).to be(false)
    end

    it "is assignable to true" do
      config.auto_reload = true
      expect(config.auto_reload).to be(true)
    end

    it "is assignable back to false" do
      config.auto_reload = true
      config.auto_reload = false
      expect(config.auto_reload).to be(false)
    end
  end

  describe "#reload_paths" do
    it "defaults to an empty array" do
      expect(config.reload_paths).to eq([])
    end

    it "accepts a list of glob patterns" do
      paths = ["app/**/*.rb", "config/*.rb"]
      config.reload_paths = paths
      expect(config.reload_paths).to eq(paths)
    end
  end

  describe "#router_logging" do
    it "defaults to false" do
      expect(config.router_logging).to be(false)
    end

    it "is assignable to true" do
      config.router_logging = true
      expect(config.router_logging).to be(true)
    end
  end

  describe "error-handling knobs" do
    describe "#error_component" do
      it "defaults to Weft::Defaults::ErrorComponent" do
        expect(config.error_component).to eq(Weft::Defaults::ErrorComponent)
      end

      it "is assignable" do
        klass = Class.new
        config.error_component = klass
        expect(config.error_component).to eq(klass)
      end
    end

    describe "#error_page" do
      it "defaults to Weft::Defaults::ErrorPage" do
        expect(config.error_page).to eq(Weft::Defaults::ErrorPage)
      end

      it "is assignable" do
        klass = Class.new
        config.error_page = klass
        expect(config.error_page).to eq(klass)
      end
    end

    describe "#not_found_page" do
      it "defaults to Weft::Defaults::NotFoundPage" do
        expect(config.not_found_page).to eq(Weft::Defaults::NotFoundPage)
      end

      it "is assignable" do
        klass = Class.new
        config.not_found_page = klass
        expect(config.not_found_page).to eq(klass)
      end
    end

    describe "#not_found_component" do
      it "defaults to Weft::Defaults::NotFoundComponent" do
        expect(config.not_found_component).to eq(Weft::Defaults::NotFoundComponent)
      end

      it "is assignable" do
        klass = Class.new
        config.not_found_component = klass
        expect(config.not_found_component).to eq(klass)
      end
    end

    describe "#verbose_error_pages" do
      it "defaults to true" do
        expect(config.verbose_error_pages).to be(true)
      end

      it "is assignable to false" do
        config.verbose_error_pages = false
        expect(config.verbose_error_pages).to be(false)
      end
    end

    describe "#htmx_errors" do
      it "defaults to :fragment" do
        expect(config.htmx_errors).to eq(:fragment)
      end

      it "accepts :redirect" do
        config.htmx_errors = :redirect
        expect(config.htmx_errors).to eq(:redirect)
      end

      it "rejects unknown values" do
        expect { config.htmx_errors = :something_else }.
          to raise_error(ArgumentError, /must be :fragment or :redirect/)
      end
    end
  end

  describe "#static_assets" do
    it "starts empty" do
      expect(config.static_assets).to eq({})
    end

    it "registers a bundle under the :default name when no name: is given" do
      config.static_assets root: "/static", from: "/app/public"
      expect(config.static_assets).to eq(default: { root: "/static", from: "/app/public" })
    end

    it "registers a bundle under a custom name" do
      config.static_assets name: :vendor, root: "/vendor", from: "/app/vendor"
      expect(config.static_assets).to eq(vendor: { root: "/vendor", from: "/app/vendor" })
    end

    it "registers multiple distinct bundles" do
      config.static_assets root: "/static", from: "/app/public"
      config.static_assets name: :vendor, root: "/vendor", from: "/app/vendor"
      expect(config.static_assets).to eq(
        default: { root: "/static", from: "/app/public" },
        vendor: { root: "/vendor", from: "/app/vendor" }
      )
    end

    it "accepts a string name and normalizes to symbol" do
      config.static_assets name: "app", root: "/static", from: "/app/public"
      expect(config.static_assets).to have_key(:app)
    end

    it "raises on a duplicate name" do
      config.static_assets name: :app, root: "/a", from: "/from-a"
      expect { config.static_assets name: :app, root: "/b", from: "/from-b" }.
        to raise_error(Weft::InvalidConfiguration, /bundle :app is already registered/)
    end

    it "raises on a duplicate :default (implicit and then implicit again)" do
      config.static_assets root: "/static", from: "/app/public"
      expect { config.static_assets root: "/elsewhere", from: "/other" }.
        to raise_error(Weft::InvalidConfiguration, /bundle :default is already registered/)
    end

    it "raises on a duplicate root URL even under a different name" do
      config.static_assets name: :app, root: "/static", from: "/app/public"
      expect { config.static_assets name: :other, root: "/static", from: "/elsewhere" }.
        to raise_error(Weft::InvalidConfiguration, %r{root "/static" is already registered \(by bundle :app\)})
    end

    it "treats trailing-slash and bare forms as duplicate roots" do
      config.static_assets name: :app, root: "/static", from: "/app/public"
      expect { config.static_assets name: :other, root: "/static/", from: "/elsewhere" }.
        to raise_error(Weft::InvalidConfiguration, /already registered/)
    end

    it "normalizes a trailing slash off the root" do
      config.static_assets root: "/static/", from: "/app/public"
      expect(config.static_assets[:default][:root]).to eq("/static")
    end

    it "requires both root: and from:" do
      expect { config.static_assets root: "/static" }.
        to raise_error(ArgumentError, /requires both/)
      expect { config.static_assets from: "/app/public" }.
        to raise_error(ArgumentError, /requires both/)
      expect { config.static_assets name: :app }.
        to raise_error(ArgumentError, /requires both/)
    end

    it "requires the root to start with a slash" do
      expect { config.static_assets root: "static", from: "/app/public" }.
        to raise_error(Weft::InvalidConfiguration, /must start with/)
    end

    it "returns a deep copy from the no-arg reader (cannot mutate internal state)" do
      config.static_assets root: "/static", from: "/app/public"
      bundles = config.static_assets
      bundles[:default][:root] = "/tampered"
      bundles[:added] = { root: "/x", from: "/y" }
      expect(config.static_assets).to eq(default: { root: "/static", from: "/app/public" })
    end
  end

  describe "#include_sse_ext" do
    it "defaults to :auto" do
      expect(config.include_sse_ext).to eq(:auto)
    end

    it "accepts :auto" do
      config.include_sse_ext = :auto
      expect(config.include_sse_ext).to eq(:auto)
    end

    it "accepts true" do
      config.include_sse_ext = true
      expect(config.include_sse_ext).to be(true)
    end

    it "accepts false" do
      config.include_sse_ext = false
      expect(config.include_sse_ext).to be(false)
    end

    it "rejects unknown symbols" do
      expect { config.include_sse_ext = :always }.
        to raise_error(ArgumentError, /must be :auto, true, or false/)
    end

    it "rejects unrelated values" do
      expect { config.include_sse_ext = "auto" }.
        to raise_error(ArgumentError, /must be :auto, true, or false/)
    end
  end

  describe "#stream_suffix" do
    it "defaults to the bare segment \"_stream\"" do
      expect(config.stream_suffix).to eq("_stream")
    end

    it "accepts a custom bare segment" do
      config.stream_suffix = "sse"
      expect(config.stream_suffix).to eq("sse")
    end

    it "rejects a non-string value" do
      expect { config.stream_suffix = :stream }.
        to raise_error(ArgumentError, /non-empty path segment/)
    end

    it "rejects a value containing a slash (Weft supplies the slash)" do
      expect { config.stream_suffix = "/stream" }.
        to raise_error(ArgumentError, /no slashes/)
    end

    it "rejects an empty string" do
      expect { config.stream_suffix = "" }.
        to raise_error(ArgumentError, /non-empty path segment/)
    end
  end

  describe "gem-level access via Weft.configure" do
    around do |example|
      original = Weft.configuration
      Weft.instance_variable_set(:@configuration, described_class.new)
      example.run
      Weft.instance_variable_set(:@configuration, original)
    end

    it "yields the configuration object" do
      Weft.configure do |c|
        expect(c).to be_a(described_class)
      end
    end

    it "persists configuration changes" do
      custom = ->(klass) { "/custom/#{klass.name}" }
      Weft.configure { |c| c.component_path = custom }

      expect(Weft.configuration.component_path).to eq(custom)
    end
  end

  describe "auto_reload apply step in Weft.configure" do
    around do |example|
      original_config = Weft.configuration
      original_applied = Weft.instance_variable_get(:@auto_reload_applied)
      Weft.instance_variable_set(:@configuration, described_class.new)
      Weft.instance_variable_set(:@auto_reload_applied, nil)
      example.run
      Weft.instance_variable_set(:@configuration, original_config)
      Weft.instance_variable_set(:@auto_reload_applied, original_applied)
    end

    it "registers Sinatra::Reloader on Weft::Router when auto_reload is true" do
      allow(Weft::Router).to receive(:register)

      Weft.configure { |c| c.auto_reload = true }

      expect(Weft::Router).to have_received(:register).with(Sinatra::Reloader).once
    end

    it "does not register when auto_reload stays false" do
      allow(Weft::Router).to receive(:register)

      Weft.configure { |c| c.auto_reload = false }

      expect(Weft::Router).not_to have_received(:register)
    end

    it "is idempotent: repeated configure calls register only once" do
      allow(Weft::Router).to receive(:register)

      Weft.configure { |c| c.auto_reload = true }
      Weft.configure { |c| c.auto_reload = true }
      Weft.configure { |c| c.auto_reload = true }

      expect(Weft::Router).to have_received(:register).with(Sinatra::Reloader).once
    end

    it "does not unregister when toggled back to false after first apply" do
      allow(Weft::Router).to receive(:register)

      Weft.configure { |c| c.auto_reload = true }
      Weft.configure { |c| c.auto_reload = false }

      expect(Weft::Router).to have_received(:register).with(Sinatra::Reloader).once
    end

    it "passes configured reload_paths through to Weft::Router.also_reload" do
      allow(Weft::Router).to receive(:register)
      allow(Weft::Router).to receive(:also_reload)

      Weft.configure do |c|
        c.auto_reload = true
        c.reload_paths = ["app/**/*.rb", "config/**/*.rb"]
      end

      expect(Weft::Router).to have_received(:also_reload).with("app/**/*.rb")
      expect(Weft::Router).to have_received(:also_reload).with("config/**/*.rb")
    end

    it "does not call also_reload when auto_reload is false" do
      allow(Weft::Router).to receive(:also_reload)

      Weft.configure do |c|
        c.reload_paths = ["app/**/*.rb"]
      end

      expect(Weft::Router).not_to have_received(:also_reload)
    end
  end

  describe "router_logging apply step in Weft.configure" do
    around do |example|
      original_config = Weft.configuration
      Weft.instance_variable_set(:@configuration, described_class.new)
      example.run
      Weft.instance_variable_set(:@configuration, original_config)
    end

    it "applies a true router_logging to Weft::Router's :logging setting" do
      allow(Weft::Router).to receive(:set)

      Weft.configure { |c| c.router_logging = true }

      expect(Weft::Router).to have_received(:set).with(:logging, true)
    end

    it "applies the default (false) when router_logging is untouched" do
      allow(Weft::Router).to receive(:set)

      Weft.configure do |_c|
        # no overrides; exercises the default apply path
      end

      expect(Weft::Router).to have_received(:set).with(:logging, false)
    end
  end
end
