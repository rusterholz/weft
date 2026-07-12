# frozen_string_literal: true

require "logger"

RSpec.describe Weft do
  it "has a version number" do
    expect(Weft::VERSION).not_to be_nil
  end

  describe ".configure" do
    it "yields the configuration object" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end
  end

  describe ".logger" do
    around do |example|
      saved = described_class.instance_variable_get(:@logger)
      described_class.instance_variable_set(:@logger, nil)
      example.run
      described_class.instance_variable_set(:@logger, saved)
    end

    it "defaults to a Logger" do
      expect(described_class.logger).to be_a(Logger)
    end

    it "memoizes the default" do
      first = described_class.logger
      expect(described_class.logger).to be(first)
    end

    it "is overridable via the writer" do
      custom = Logger.new(IO::NULL)
      described_class.logger = custom
      expect(described_class.logger).to be(custom)
    end
  end

  describe ".configure log level application" do
    around do |example|
      saved_logger = described_class.instance_variable_get(:@logger)
      saved_config = described_class.instance_variable_get(:@configuration)
      described_class.instance_variable_set(:@logger, nil)
      described_class.instance_variable_set(:@configuration, nil)
      example.run
      described_class.instance_variable_set(:@logger, saved_logger)
      described_class.instance_variable_set(:@configuration, saved_config)
    end

    it "applies the default :info level" do
      described_class.configure do |_c|
        # no overrides; exercises the default :info apply path
      end
      expect(described_class.logger.level).to eq(Logger::INFO)
    end

    it "applies a configured level" do
      described_class.configure { |c| c.log_level = :warn }
      expect(described_class.logger.level).to eq(Logger::WARN)
    end
  end
end
