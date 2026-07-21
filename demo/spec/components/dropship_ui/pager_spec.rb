# frozen_string_literal: true

require "spec_helper"

# Real named fixtures (constants) so the panel's route derives from its name and
# the pager's builder_method resolves. The pager reaches its enclosing panel via
# `enclosing` for the swap target (the panel's route + DOM id) and push_url (the
# panel's declared page_class); the fake panel supplies those and forwards each
# example's pager attrs through a class-level accessor.
module PagerSpecFixtures
  class Page < Weft::Page
    def self.name = "FakePage"
    self.page_path = "/fake"
  end

  class Panel < Weft::Component
    def self.name = "FakeTarget"

    class << self
      attr_accessor :pager_attrs
    end

    def page_class = PagerSpecFixtures::Page

    def build(attributes = {})
      super
      pager(**self.class.pager_attrs)
    end
  end
end

RSpec.describe DropshipUI::Pager, type: :component do
  def render(**pager_attrs)
    PagerSpecFixtures::Panel.pager_attrs = pager_attrs
    render_weft_html { insert_tag(PagerSpecFixtures::Panel) }
  end

  it "renders nothing visible when total is 0" do
    html = render(page_num: 1, per_page: 25, total: 0)
    expect(html).not_to include("Page ")
    expect(html).not_to include("Prev")
    expect(html).not_to include("Next")
  end

  it "renders offset text and page-of-page indicator" do
    html = render(page_num: 3, per_page: 25, total: 120)
    expect(html).to include("51–75 of 120")
    expect(html).to include("Page 3 of 5")
  end

  it "renders Prev and Next buttons in the middle of the range" do
    html = render(page_num: 3, per_page: 25, total: 120)
    expect(html).to include("Prev")
    expect(html).to include("Next")
    expect(html).to match(/<button[^>]*>← Prev/)
    expect(html).to match(/<button[^>]*>Next →/)
  end

  it "disables Prev on the first page" do
    html = render(page_num: 1, per_page: 25, total: 120)
    expect(html).to match(/<span[^>]*disabled[^>]*>← Prev/)
  end

  it "disables Next on the last page" do
    html = render(page_num: 5, per_page: 25, total: 120)
    expect(html).to match(/<span[^>]*disabled[^>]*>Next →/)
  end

  it "wires buttons through the :paginate preset (click trigger + replace swap)" do
    html = render(page_num: 2, per_page: 25, total: 120)
    expect(html).to include('hx-target="#fake-target"')
    expect(html).to include('hx-swap="outerHTML"')
    expect(html).to include('hx-trigger="click"')
  end

  it "builds hx-get URLs from the enclosing panel's component path with page params" do
    html = render(page_num: 2, per_page: 25, total: 120)
    expect(html).to include('hx-get="/_components/fake_target?page=1"')
    expect(html).to include('hx-get="/_components/fake_target?page=3"')
  end

  it "builds push_url URLs from the panel's page_class page path" do
    html = render(page_num: 2, per_page: 25, total: 120)
    expect(html).to include('hx-push-url="/fake?page=3"')
  end

  it "omits page=1 from push_url (bare page URL for page 1)" do
    html = render(page_num: 2, per_page: 25, total: 120)
    expect(html).to include('hx-push-url="/fake"') # Prev points to page 1 → bare URL
  end

  it "preserves extra_params in both navigation and push URLs" do
    html = render(page_num: 2, per_page: 25, total: 120, extra_params: { status: "submitted" })
    expect(html).to include("status=submitted")
    expect(html).to match(/hx-push-url="[^"]*status=submitted/)
  end
end
