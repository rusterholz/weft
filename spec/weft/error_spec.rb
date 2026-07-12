# frozen_string_literal: true

require "weft/error"

RSpec.describe Weft::Error do
  it "is a subclass of StandardError" do
    expect(described_class.superclass).to eq(StandardError)
  end

  it "can be rescued with Weft::Error" do
    expect { raise described_class, "test" }.to raise_error(described_class)
  end

  describe Weft::HTTPError do
    it "is a subclass of Weft::Error" do
      expect(described_class.superclass).to eq(Weft::Error)
    end

    it "reports nil status on the abstract base (class and instance)" do
      expect(described_class.status).to be_nil
      expect(described_class.new.status).to be_nil
    end

    describe "concrete subclasses" do
      {
        Weft::NotFound => 404,
        Weft::Unauthorized => 401,
        Weft::Forbidden => 403,
        Weft::Unprocessable => 422,
        Weft::InternalError => 500
      }.each do |klass, expected_status|
        it "#{klass.name} reports HTTP status #{expected_status} (class and instance)" do
          expect(klass.status).to eq(expected_status)
          expect(klass.new.status).to eq(expected_status)
        end

        it "#{klass.name} is a Weft::HTTPError and a Weft::Error" do
          expect(klass.ancestors).to include(described_class, Weft::Error)
        end
      end
    end

    it "allows user subclassing with a custom status" do
      custom_klass = Class.new(described_class) do
        def self.status = 429
      end
      expect(custom_klass.status).to eq(429)
      expect(custom_klass.new.status).to eq(429)
    end

    it "subclasses of concrete subclasses inherit status by default" do
      custom_klass = Class.new(Weft::NotFound)
      expect(custom_klass.status).to eq(404)
      expect(custom_klass.new.status).to eq(404)
    end
  end
end
