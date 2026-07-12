# frozen_string_literal: true

require_relative "lib/weft/version"

Gem::Specification.new do |spec|
  spec.name          = "weft"
  spec.version       = Weft::VERSION
  spec.authors       = ["Andy Rusterholz"]
  spec.email         = ["andyrusterholz@gmail.com"]

  spec.summary       = "Component-oriented hypermedia for Ruby."
  spec.description = <<~DESC.gsub(/\s+/, " ").strip
    Weft is a rapid web development framework where front-end components declare
    what behaviors are possible, and the back-end routing and request handling is
    derived automatically. No routes. No controllers. Just Weft.
  DESC
  spec.homepage      = "https://github.com/rusterholz/weft"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # allowed_push_host removed — this is a public gem, rubygems.org is the default
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rusterholz/weft"
  spec.metadata["changelog_uri"] = "https://github.com/rusterholz/weft/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Explicit file list - audit before each release (see docs/development.md).
  # Maintainer-facing docs stay out of the packaged gem.
  excluded_docs = %w[internal development]
  spec.files = Dir.glob(
    %w[lib/**/* docs/**/* LICENSE.txt README.md CHANGELOG.md]
  ).reject { |f| excluded_docs.any? { |doc| f.include?("docs/#{doc}.md") } }
  spec.require_paths = ["lib"]

  # Dev dependencies are listed in the Gemfile.

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "arbre", ">= 1.7"
  spec.add_dependency "sinatra", ">= 3.0"
  spec.add_dependency "sinatra-contrib", ">= 3.0"
end
