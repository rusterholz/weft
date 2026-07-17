# frozen_string_literal: true

RSpec.describe Weft::Redirect do
  describe ".to with string path" do
    it "stores the path and resolves it as the URL" do
      redirect = described_class.to("/orders/42")

      expect(redirect.url).to eq("/orders/42")
    end

    it "is a Redirect instance" do
      redirect = described_class.to("/orders/42")

      expect(redirect).to be_a(described_class)
    end
  end

  describe ".to with Page subclass" do
    it "resolves the URL from the page path pattern and params" do
      page_class = Class.new(Weft::Page) do
        def self.name = "RedirectTargetPage"
        self.page_path = "/orders/:order_id"
        param :order_id
      end

      redirect = described_class.to(page_class, order_id: "abc-123")

      expect(redirect.url).to eq("/orders/abc-123")
    end

    it "resolves a non-parameterized page path" do
      dashboard = Class.new(Weft::Page) do
        def self.name = "RedirectDashPage"
        self.page_path = "/dashboard"
      end

      redirect = described_class.to(dashboard)

      expect(redirect.url).to eq("/dashboard")
    end
  end

  describe ".new" do
    it "is private — construct via .to" do
      expect { described_class.new("/orders/42") }.to raise_error(NoMethodError, /private method/)
    end
  end

  describe "Weft.redirect convenience wrapper" do
    it "delegates to Weft::Redirect.to" do
      redirect = Weft.redirect("/orders/42")

      expect(redirect).to be_a(described_class)
      expect(redirect.url).to eq("/orders/42")
    end
  end
end
