# frozen_string_literal: true

# Axes: Arbre version × ActiveSupport version
# Arbre 1.7 requires AS >= 3.0; AS 6.1 is the oldest we appraise (and the
# gemspec floor — the two must move together).
# Arbre 2.x requires AS >= 7.0, so the 6.1 leg only rides with Arbre 1.7.

ARBRE_VERSIONS = {
  "arbre-1.7" => "~> 1.7.0",
  "arbre-2.2" => "~> 2.2.0"
}.freeze

# AS versions paired with each Arbre version.
# Arbre 1.7 users are likely on AS 6.1–7.1 (legacy ActiveAdmin installs and
# mid-upgrade shops: modern Ruby, Rails still 6.1). Arbre 2.x users span the
# full modern range.
ARBRE_AS_MATRIX = {
  "arbre-1.7" => {
    "as-6.1" => "~> 6.1.0",
    "as-7.0" => "~> 7.0.0",
    "as-7.1" => "~> 7.1.0"
  },
  "arbre-2.2" => {
    "as-7.0" => "~> 7.0.0",
    "as-7.2" => "~> 7.2.0",
    "as-8.0" => "~> 8.0.0"
  }
}.freeze

ARBRE_AS_MATRIX.each do |arbre_name, as_versions|
  arbre_version = ARBRE_VERSIONS[arbre_name]

  as_versions.each do |as_name, as_version|
    appraise "#{arbre_name}-#{as_name}" do
      gem "arbre", arbre_version
      gem "activesupport", as_version
    end
  end
end
