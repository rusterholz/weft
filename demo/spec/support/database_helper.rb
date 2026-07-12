# frozen_string_literal: true

module DatabaseHelper
  def self.setup!
    # Ensure test database exists and is migrated
    db_path = File.join(APP_ROOT, "db", "test.sqlite3")
    FileUtils.rm_f(db_path)

    migrations_path = File.join(APP_ROOT, "db", "migrate")
    ActiveRecord::MigrationContext.new(migrations_path).migrate
  end
end
