# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::Page, type: :component do
  let(:concrete_page) do
    Class.new(described_class) do
      def self.name = "TestPage"
    end
  end

  def render_concrete(**attrs)
    klass = concrete_page
    render_arbre_html { insert_tag(klass, **attrs) }
  end

  it "renders as an html element with DOCTYPE" do
    html = render_concrete
    expect(html).to start_with("<!DOCTYPE html>")
    expect(html).to include("<html")
  end

  it "defaults to Dropship Co. title (company branding)" do
    expect(render_concrete).to include("<title>Dropship Co.</title>")
  end

  it "accepts a custom title that overrides the default" do
    expect(render_concrete(title: "Specific Page")).to include("<title>Specific Page</title>")
  end

  it "includes Bootstrap stylesheet (the design system's framework choice)" do
    expect(render_concrete).to include("bootstrap")
  end

  it "includes htmx (auto-registered by Weft::Page)" do
    expect(render_concrete).to include("htmx.org")
  end

  it "includes htmx responseHandling config" do
    expect(render_concrete).to include("responseHandling")
  end

  it "links the design-system stylesheet (served by the gem static_assets bundle)" do
    html = render_concrete
    expect(html).to include('href="/static/css/design-system.css"')
    expect(html).to include('rel="stylesheet"')
  end

  it "does not itself register the htmx-ext-sse script (gem auto-emits it when components push)" do
    allow(Weft.registry).to receive(:any_sse_components?).and_return(false)
    expect(render_concrete).not_to include("htmx-ext-sse")
  end

  it "does not render any navbar (that lives in the app's ApplicationPage)" do
    expect(render_concrete).not_to include("<nav")
    expect(render_concrete).not_to include('class="navbar-brand"')
  end
end
