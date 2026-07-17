# frozen_string_literal: true

require "arbre"

RSpec.describe Weft::Page do
  it "renders as an html element with DOCTYPE" do
    html = Arbre::Context.new { weft_page }.to_s
    expect(html).to start_with("<!DOCTYPE html>")
    expect(html).to include("<html")
  end

  it "includes head with meta and title" do
    html = Arbre::Context.new { weft_page }.to_s
    expect(html).to include('<meta charset="utf-8"/>')
    expect(html).to include("<title>Weft</title>")
  end

  it "accepts a custom title" do
    html = Arbre::Context.new { weft_page title: "My App" }.to_s
    expect(html).to include("<title>My App</title>")
  end

  it "redirects block content into the body" do
    html = Arbre::Context.new { weft_page { h1 "Hello" } }.to_s
    expect(html).to match(%r{<body>.*<h1>Hello</h1>.*</body>}m)
  end

  it "auto-includes htmx script by default" do
    html = Arbre::Context.new { weft_page }.to_s
    expect(html).to include("htmx.org")
  end

  it "omits htmx script when include_htmx is false" do
    original = Weft.configuration.include_htmx
    Weft.configuration.include_htmx = false
    html = Arbre::Context.new { weft_page }.to_s
    expect(html).not_to include("htmx.org")
  ensure
    Weft.configuration.include_htmx = original
  end

  it "includes htmx responseHandling configuration" do
    html = Arbre::Context.new { weft_page }.to_s
    expect(html).to include("responseHandling")
    expect(html).to include("[45]..")
  end

  describe "htmx-ext-sse script auto-inclusion" do
    around do |example|
      original = Weft.configuration.include_sse_ext
      example.run
    ensure
      Weft.configuration.include_sse_ext = original
    end

    context "with include_sse_ext = :auto (default)" do
      it "omits the sse.js script when no registered component pushes" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(false)
        html = Arbre::Context.new { weft_page }.to_s
        expect(html).not_to include("htmx-ext-sse")
      end

      it "includes the sse.js script when a registered component pushes" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(true)
        html = Arbre::Context.new { weft_page }.to_s
        expect(html).to include("htmx-ext-sse")
        expect(html).to include(Weft::Page::HTMX_SSE_SRC)
      end

      it "emits sse.js after the htmx core script" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(true)
        html = Arbre::Context.new { weft_page }.to_s
        htmx_index = html.index(Weft::Page::HTMX_SRC)
        sse_index = html.index(Weft::Page::HTMX_SSE_SRC)
        expect(htmx_index).to be < sse_index
      end

      it "pins the sse.js script with subresource integrity" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(true)
        html = Arbre::Context.new { weft_page }.to_s
        sse_tag = html[/<script[^>]*htmx-ext-sse[^>]*>/]
        expect(sse_tag).to include('integrity="sha384-')
        expect(sse_tag).to include('crossorigin="anonymous"')
      end
    end

    context "with include_sse_ext = true" do
      it "always includes the sse.js script, even when no component pushes" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(false)
        Weft.configuration.include_sse_ext = true
        html = Arbre::Context.new { weft_page }.to_s
        expect(html).to include("htmx-ext-sse")
      end
    end

    context "with include_sse_ext = false" do
      it "never includes the sse.js script, even when a component pushes" do
        allow(Weft.registry).to receive(:any_sse_components?).and_return(true)
        Weft.configuration.include_sse_ext = false
        html = Arbre::Context.new { weft_page }.to_s
        expect(html).not_to include("htmx-ext-sse")
      end
    end
  end

  describe "register_stylesheet" do
    it "includes registered stylesheets in the head" do
      page_class = Class.new(described_class) do
        def self.name = "StyledPage"
        register_stylesheet "https://cdn.example.com/app.css"
      end

      html = Arbre::Context.new { insert_tag(page_class) }.to_s
      expect(html).to include('href="https://cdn.example.com/app.css"')
      expect(html).to include('rel="stylesheet"')
    end
  end

  describe "register_script" do
    it "includes registered scripts in the head" do
      page_class = Class.new(described_class) do
        def self.name = "ScriptedPage"
        register_script "https://cdn.example.com/app.js", defer: "defer"
      end

      html = Arbre::Context.new { insert_tag(page_class) }.to_s
      expect(html).to include('src="https://cdn.example.com/app.js"')
      expect(html).to include('defer="defer"')
    end
  end

  describe "resolve-against-root for registered assets" do
    around do |example|
      original = Weft.configuration
      Weft.instance_variable_set(:@configuration, Weft::Configuration.new)
      example.run
    ensure
      Weft.instance_variable_set(:@configuration, original)
    end

    def render_with(stylesheet: nil, stylesheet_assets: nil, script: nil, script_assets: nil)
      klass = Class.new(described_class) { def self.name = "AssetPage" }
      klass.register_stylesheet(stylesheet, assets: stylesheet_assets) if stylesheet
      klass.register_script(script, assets: script_assets) if script
      Arbre::Context.new { insert_tag(klass) }.to_s
    end

    context "with no bundles configured" do
      it "passes a bare-relative stylesheet through unchanged" do
        expect(render_with(stylesheet: "css/app.css")).to include('href="css/app.css"')
      end

      it "raises if assets: names a bundle that does not exist" do
        klass = Class.new(described_class) { def self.name = "BadPage" }
        klass.register_stylesheet "css/app.css", assets: :missing
        expect { Arbre::Context.new { insert_tag(klass) }.to_s }.
          to raise_error(Weft::InvalidUsage, /bundle :missing.*Configured bundles: \[\]/m)
      end
    end

    context "with a :default bundle (no explicit name in config)" do
      before { Weft.configure { |c| c.static_assets root: "/static", from: "/app/public" } }

      it "resolves bare-relative stylesheets against the :default bundle" do
        expect(render_with(stylesheet: "css/app.css")).to include('href="/static/css/app.css"')
      end

      it "resolves bare-relative scripts against the :default bundle" do
        expect(render_with(script: "js/app.js")).to include('src="/static/js/app.js"')
      end

      it "passes an https URL through unchanged" do
        html = render_with(stylesheet: "https://cdn.example.com/x.css")
        expect(html).to include('href="https://cdn.example.com/x.css"')
        expect(html).not_to include("/static/https")
      end

      it "passes a protocol-relative URL through unchanged" do
        expect(render_with(stylesheet: "//cdn.example.com/x.css")).to include('href="//cdn.example.com/x.css"')
      end

      it "passes a leading-slash absolute path through unchanged" do
        html = render_with(stylesheet: "/already/absolute.css")
        expect(html).to include('href="/already/absolute.css"')
        expect(html).not_to include("/static/already")
      end

      it "raises if an absolute URL is registered with an assets: kwarg" do
        klass = Class.new(described_class) { def self.name = "BadAbsolutePage" }
        klass.register_stylesheet "https://cdn.example.com/x.css", assets: :default
        expect { Arbre::Context.new { insert_tag(klass) }.to_s }.
          to raise_error(Weft::InvalidUsage, /assets:.*absolute URLs/m)
      end
    end

    context "with a single non-default bundle configured" do
      before { Weft.configure { |c| c.static_assets name: :app, root: "/static", from: "/app/public" } }

      it "passes a bare-relative path through unchanged (no :default to resolve against)" do
        expect(render_with(stylesheet: "css/app.css")).to include('href="css/app.css"')
      end

      it "resolves when assets: kwarg names the bundle" do
        expect(render_with(stylesheet: "css/app.css", stylesheet_assets: :app)).to include('href="/static/css/app.css"')
      end

      it "raises when assets: names an unknown bundle" do
        klass = Class.new(described_class) { def self.name = "BadAssetsPage" }
        klass.register_stylesheet "css/app.css", assets: :missing
        expect { Arbre::Context.new { insert_tag(klass) }.to_s }.
          to raise_error(Weft::InvalidUsage, /bundle :missing.*Configured bundles: \[:app\]/m)
      end
    end

    context "with multiple bundles, one named :default" do
      before do
        Weft.configure do |c|
          c.static_assets root: "/static", from: "/app/public"
          c.static_assets name: :vendor, root: "/vendor", from: "/app/vendor"
        end
      end

      it "implicit assets: resolves against :default" do
        expect(render_with(stylesheet: "css/app.css")).to include('href="/static/css/app.css"')
      end

      it "explicit assets: :vendor resolves against the named bundle" do
        expect(render_with(stylesheet: "tw/tw.css", stylesheet_assets: :vendor)).to include('href="/vendor/tw/tw.css"')
      end

      it "preserves behavior of the :default-resolving call sites when new bundles are added" do
        # Sanity check on the stability promise: adding a second bundle does
        # not silently change how an existing bare-relative call site resolves.
        before_html = render_with(stylesheet: "css/app.css")
        Weft.configure { |c| c.static_assets name: :extra, root: "/extra", from: "/app/extra" }
        after_html = render_with(stylesheet: "css/app.css")
        expect(after_html).to eq(before_html)
      end
    end

    context "with multiple bundles, none named :default" do
      before do
        Weft.configure do |c|
          c.static_assets name: :app,    root: "/static", from: "/app/public"
          c.static_assets name: :vendor, root: "/vendor", from: "/app/vendor"
        end
      end

      it "passes bare-relative paths without assets: through unchanged" do
        expect(render_with(stylesheet: "css/app.css")).to include('href="css/app.css"')
      end

      it "still resolves explicit assets: :app" do
        expect(render_with(stylesheet: "css/app.css", stylesheet_assets: :app)).to include('href="/static/css/app.css"')
      end
    end
  end

  describe "page_path" do
    it "resolves a parameterized path by interpolating params" do
      page_class = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
      end

      expect(page_class.resolve_page_path(order_id: "42")).to eq("/orders/42")
    end

    it "defaults to class-name-derived path for non-parameterized pages" do
      page_class = Class.new(described_class) do
        def self.name = "DashboardPage"
      end

      expect(page_class.resolve_page_path).to eq("/dashboard")
    end

    it "derives a default path even when the name lacks the 'Page' suffix" do
      page_class = Class.new(described_class) do
        def self.name = "BazBar"
      end

      expect(page_class.resolve_page_path).to eq("/baz_bar")
    end

    it "derives a namespaced default path from module nesting" do
      page_class = Class.new(described_class) do
        def self.name = "Admin::ReportsPage"
      end

      expect(page_class.resolve_page_path).to eq("/admin/reports")
    end

    it "raises a helpful error resolving a page whose name has no usable stem" do
      page_class = Class.new(described_class) do
        def self.name = "Foo::Page"
      end

      expect { page_class.resolve_page_path }.
        to raise_error(Weft::InvalidDefinition, /no resolvable default page_path.*abstract!/m)
    end

    it "raises when parameterized page omits page_path" do
      page_class = Class.new(described_class) do
        def self.name = "MissingPathPage"
        param :order_id
      end

      expect { page_class.resolve_page_path }.to raise_error(Weft::InvalidDefinition, /page_path/)
    end

    it "inherits page_path from parent" do
      parent = Class.new(described_class) do
        def self.name = "ParentPage"
        self.page_path = "/parent/:id"
      end
      child = Class.new(parent) do
        def self.name = "ChildPage"
        param :id
      end

      expect(child.resolve_page_path(id: "7")).to eq("/parent/7")
    end
  end

  describe "param DSL on Page" do
    it "declares and resolves attributes in build" do
      page_class = Class.new(described_class) do
        def self.name = "AttrPage"
        self.page_path = "/test/:item_id"
        param :item_id

        def build(attributes = {})
          super
          div { text_node "item=#{params.item_id}" }
        end
      end

      html = Weft::Context.new({}, nil, wire_params: { "item_id" => "99" }) { insert_tag(page_class) }.to_s

      expect(html).to include("item=99")
    end
  end

  describe "inheritance" do
    it "inherits stylesheets and scripts from parent" do
      parent = Class.new(described_class) do
        def self.name = "BasePage"
        register_stylesheet "https://cdn.example.com/base.css"
        register_script "https://cdn.example.com/base.js"
      end
      child = Class.new(parent) do
        def self.name = "ChildPage"
        register_stylesheet "https://cdn.example.com/child.css"
      end

      html = Arbre::Context.new { insert_tag(child) }.to_s
      expect(html).to include("base.css")
      expect(html).to include("base.js")
      expect(html).to include("child.css")
    end
  end

  describe "register_inline_css" do
    it "emits the registered inline CSS inside a <style> tag in the head" do
      page_class = Class.new(described_class) do
        def self.name = "InlineStyledPage"
        register_inline_css ".foo { color: red; }"
      end

      html = Arbre::Context.new { insert_tag(page_class) }.to_s
      expect(html).to match(%r{<head>.*<style>\.foo \{ color: red; \}</style>.*</head>}m)
    end

    it "emits each entry as its own <style> tag (source attribution stays visible)" do
      page_class = Class.new(described_class) do
        def self.name = "MultiStyledPage"
        register_inline_css ".one { color: red; }"
        register_inline_css ".two { color: blue; }"
      end

      html = Arbre::Context.new { insert_tag(page_class) }.to_s
      expect(html).to include("<style>.one { color: red; }</style>")
      expect(html).to include("<style>.two { color: blue; }</style>")
    end

    it "inherits parent CSS and appends child CSS (composable, not replacing)" do
      parent = Class.new(described_class) do
        def self.name = "BaseStyledPage"
        register_inline_css ".base { color: red; }"
      end
      child = Class.new(parent) do
        def self.name = "ChildStyledPage"
        register_inline_css ".child { color: blue; }"
      end

      html = Arbre::Context.new { insert_tag(child) }.to_s
      expect(html).to include("<style>.base { color: red; }</style>")
      expect(html).to include("<style>.child { color: blue; }</style>")
    end

    it "does not strip or escape the CSS (it goes in literally)" do
      page_class = Class.new(described_class) do
        def self.name = "RawCssPage"
        register_inline_css "/* comment */ a > b::after { content: '>'; }"
      end

      html = Arbre::Context.new { insert_tag(page_class) }.to_s
      expect(html).to include("/* comment */ a > b::after { content: '>'; }")
    end
  end

  describe ".routable?" do
    it "is routable when page_path is explicitly declared" do
      page_class = Class.new(described_class) do
        def self.name = "ExplicitPathPage"
        self.page_path = "/custom"
      end

      expect(page_class).to be_routable
    end

    it "is routable when class name has a non-empty stem ending in Page" do
      page_class = Class.new(described_class) do
        def self.name = "DashboardPage"
      end

      expect(page_class).to be_routable
    end

    it "is not routable for a class named just 'Page' (empty stem)" do
      page_class = Class.new(described_class) do
        def self.name = "Page"
      end

      expect(page_class).not_to be_routable
    end

    it "is routable for a class whose name does not end with 'Page' (parity with components)" do
      page_class = Class.new(described_class) do
        def self.name = "Dashboard"
      end

      expect(page_class).to be_routable
    end

    it "is not routable for an anonymous class with no name" do
      page_class = Class.new(described_class)

      expect(page_class).not_to be_routable
    end

    describe "abstract! and routable! overrides" do
      it "abstract! makes a routable page non-routable" do
        page_class = Class.new(described_class) do
          def self.name = "AbstractedPage"
          self.page_path = "/whatever"
          abstract!
        end

        expect(page_class).not_to be_routable
      end

      it "abstract! does not percolate — concrete subclass is routable again" do
        parent = Class.new(described_class) do
          def self.name = "AbstractParentPage"
          abstract!
        end
        child = Class.new(parent) do
          def self.name = "ConcreteChildPage"
        end

        expect(parent).not_to be_routable
        expect(child).to be_routable
      end

      it "routable! forces routability when inference says no" do
        page_class = Class.new(described_class) do
          def self.name = "Page"
          routable!
          self.page_path = "/forced"
        end

        expect(page_class).to be_routable
      end

      it "routable! does not percolate to subclasses" do
        parent = Class.new(described_class) do
          def self.name = "Page"
          routable!
          self.page_path = "/forced-parent"
        end
        child = Class.new(parent) do
          def self.name = "Page"
        end

        expect(parent).to be_routable
        expect(child).not_to be_routable
      end
    end
  end

  describe "Registry.match_page (regression)" do
    it "does not match a non-routable bare 'Page' subclass against /" do
      Class.new(described_class) do
        def self.name = "Page"
      end

      expect(Weft.registry.match_page("/")).to be_nil
    end

    it "skips abstract! pages even when their page_path would otherwise match" do
      abstract = Class.new(described_class) do
        def self.name = "AbstractMatchPage"
        self.page_path = "/abstract-match"
        abstract!
      end
      # Sanity: it's registered but not routable.
      expect(Weft.registry.pages).to include(abstract)
      expect(Weft.registry.match_page("/abstract-match")).to be_nil
    end
  end

  describe ".redirect_url" do
    it "interpolates :param segments from params" do
      page = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
      end

      expect(page.redirect_url(order_id: 42)).to eq("/orders/42")
    end

    it "appends declared non-param params as query string" do
      page = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
        param :highlight_section
      end

      expect(page.redirect_url(order_id: 42, highlight_section: "items")).
        to eq("/orders/42?highlight_section=items")
    end

    it "discards params not in the page's declared schema" do
      page = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
      end

      url = page.redirect_url(order_id: 42, junk: "leak", another: "x")
      expect(url).to eq("/orders/42")
    end

    it "omits nil-valued params from the query string" do
      page = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
        param :highlight_section
      end

      expect(page.redirect_url(order_id: 42, highlight_section: nil)).
        to eq("/orders/42")
    end

    it "URL-encodes query string values" do
      page = Class.new(described_class) do
        def self.name = "OrderDetailPage"
        self.page_path = "/orders/:order_id"
        param :order_id
        param :note
      end

      expect(page.redirect_url(order_id: 42, note: "hello world")).
        to eq("/orders/42?note=hello+world")
    end
  end
end
