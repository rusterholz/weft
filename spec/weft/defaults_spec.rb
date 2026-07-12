# frozen_string_literal: true

RSpec.describe "Weft::Defaults" do
  around do |example|
    original = Weft.configuration.verbose_error_pages
    example.run
    Weft.configuration.verbose_error_pages = original
  end

  describe Weft::Defaults::ErrorComponent do
    it "is not auto-routable (abstract)" do
      expect(described_class.routable?).to be(false)
    end

    it "declares the auto-injected attributes" do
      keys = described_class.attributes.keys
      expect(keys).to include(:exception, :request_path, :status_code)
    end

    it "renders verbose info when verbose_error_pages is true" do
      Weft.configuration.verbose_error_pages = true
      error = ArgumentError.new("bad arg")
      html = described_class.render(exception: error, request_path: "/x", status_code: 500)

      expect(html).to include("ArgumentError")
      expect(html).to include("bad arg")
    end

    it "renders generic copy when verbose_error_pages is false" do
      Weft.configuration.verbose_error_pages = false
      error = ArgumentError.new("bad arg")
      html = described_class.render(exception: error, request_path: "/x", status_code: 500)

      expect(html).not_to include("ArgumentError")
      expect(html).not_to include("bad arg")
      expect(html).to match(/something went wrong/i)
    end

    it "is safe to render without an exception (e.g. redirect path)" do
      Weft.configuration.verbose_error_pages = true
      html = described_class.render(exception: nil, request_path: "/x", status_code: 500)
      expect(html).to match(/something went wrong/i)
    end
  end

  describe Weft::Defaults::ErrorPage do
    it "is a Weft::Page" do
      expect(described_class.ancestors).to include(Weft::Page)
    end

    it "declares the auto-injected attributes" do
      keys = described_class.attributes.keys
      expect(keys).to include(:exception, :request_path, :status_code)
    end

    it "has a routable page_path" do
      expect(described_class.routable?).to be(true)
      expect(described_class.page_path).to be_a(String)
    end

    it "renders as a full HTML document containing the ErrorComponent" do
      Weft.configuration.verbose_error_pages = true
      error = ArgumentError.new("bad arg")
      html = described_class.render(exception: error, request_path: "/x", status_code: 500)

      expect(html).to start_with("<!DOCTYPE html>")
      expect(html).to include("ArgumentError")
      expect(html).to include("bad arg")
    end
  end

  describe Weft::Defaults::NotFoundComponent do
    it "is not auto-routable" do
      expect(described_class.routable?).to be(false)
    end

    it "declares :request_path and :status_code auto-injected attributes" do
      keys = described_class.attributes.keys
      expect(keys).to include(:request_path, :status_code)
    end

    it "renders the request_path when verbose" do
      Weft.configuration.verbose_error_pages = true
      html = described_class.render(request_path: "/no-such-thing", status_code: 404)
      expect(html).to include("/no-such-thing")
    end

    it "renders generic copy when non-verbose" do
      Weft.configuration.verbose_error_pages = false
      html = described_class.render(request_path: "/no-such-thing", status_code: 404)
      expect(html).not_to include("/no-such-thing")
      expect(html).to match(/not found/i)
    end
  end

  describe Weft::Defaults::NotFoundPage do
    it "is a Weft::Page" do
      expect(described_class.ancestors).to include(Weft::Page)
    end

    it "is routable with an explicit page_path" do
      expect(described_class.routable?).to be(true)
      expect(described_class.page_path).to be_a(String)
    end

    it "renders as a full HTML document" do
      Weft.configuration.verbose_error_pages = true
      html = described_class.render(request_path: "/missing", status_code: 404)

      expect(html).to start_with("<!DOCTYPE html>")
      expect(html).to include("/missing")
    end
  end
end
