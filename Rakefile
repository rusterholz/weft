# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

namespace :gemfile do
  # Only the root lockfile is committed, so it's the only one that has to carry
  # every platform. The Appraisal lockfiles are generated per machine (and
  # gitignored), and CI resolves them fresh, so whatever platform it resolves on
  # is the right one there.
  desc "Ensure all platforms are present in Gemfile.lock"
  task :platforms do
    platforms = %w[ruby x86_64-darwin arm64-darwin x86_64-linux]
    platform_args = platforms.join(" ")

    # Always re-lock with all platforms - this is idempotent and ensures:
    # 1. Lockfile is in sync with gemspec (catches missing dependencies)
    # 2. All platform-specific gem variants are resolved
    lock_with_platforms = lambda do |gemfile_path|
      env = gemfile_path == "Gemfile" ? {} : { "BUNDLE_GEMFILE" => gemfile_path }
      puts "Locking #{gemfile_path} with platforms: #{platforms.join(', ')}"
      system(env, "bundle lock --add-platform #{platform_args}") || abort("Failed to lock #{gemfile_path}")
    end

    lock_with_platforms.call("Gemfile")

    puts "\nGemfile.lock updated with platforms: #{platforms.join(', ')}"
  end
end
