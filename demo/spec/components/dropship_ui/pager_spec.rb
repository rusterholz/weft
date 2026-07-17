# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::Pager, type: :component do
  # A fake target component class — Pager passes its class + DOM id to the
  # :paginate preset expansion, which renders htmx attrs that load the
  # target back into the target selector.
  let(:fake_target_class) do
    Class.new(Weft::Component) do
      def self.name = "FakeTarget"
      param :page, default: 1
    end
  end

  # A fake target page class — Pager uses its resolve_page_path for push_url.
  let(:fake_page_class) do
    Class.new(Weft::Page) do
      def self.name = "FakePage"
      self.page_path = "/fake"
    end
  end

  def render(**attrs)
    tc = fake_target_class
    pc = fake_page_class
    defaults = { target_class: tc, target_id: "fake-target", target_page_class: pc }
    render_weft_html { pager(**defaults, **attrs) }
  end

  it "renders nothing visible when total is 0" do
    html = render(page_num: 1, per_page: 25, total: 0)
    # Wrapper exists but is empty (no offset text or buttons)
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
    # Neither should be the disabled span
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

  it "builds hx-get URLs from the target_class component path with page params" do
    html = render(page_num: 2, per_page: 25, total: 120)
    expect(html).to include('hx-get="/_components/fake_target?page=1"')
    expect(html).to include('hx-get="/_components/fake_target?page=3"')
  end

  it "builds push_url URLs from the target_page_class page path" do
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
