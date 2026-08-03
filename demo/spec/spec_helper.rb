# frozen_string_literal: true

ENV["APP_ENV"] = "test"

require_relative "../config/environment"
require_relative "support/arbre_helper"
require_relative "support/database_helper"
require_relative "support/request_helper"

RSpec.configure do |config|
  config.include ArbreHelper, type: :component
  config.include RequestHelper, type: :request

  config.before(:suite) do
    DatabaseHelper.setup!
  end

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
