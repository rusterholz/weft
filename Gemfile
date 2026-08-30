# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Test-only. Weft promises that `strict: false` coerces exactly as
# ActiveModel::Type does, and spec/weft/activemodel_parity_spec.rb checks that
# against the real thing rather than against a remembered table. Deliberately
# NOT a runtime dependency: weft implements its own coercions so a standalone
# Sinatra app pulls in nothing extra, and this is what catches the drift.
gem "activemodel", ">= 6.1"
gem "appraisal", "~> 2.5"
gem "bundler", "~> 2.7"
# Default gem through Ruby 3.3, bundled from 3.4 — must be declared, exactly as
# the gemspec declares bigdecimal. Only the activemodel above needs it: through
# ActiveSupport 7.0, `active_support/notifications` requires mutex_m, so loading
# ActiveModel on Ruby 3.4 fails without this on the oldest appraisal rows. Weft
# itself never reaches that path (verified: `require "weft"` loads neither).
gem "mutex_m"
# Fix for OpenSSL 3.6.0 CRL verification bug on macOS
# See: https://github.com/ruby/openssl/issues/949
gem "openssl", ">= 3.2.2"
gem "parallel", "~> 1.24" # transitive (rubocop); 2.x needs Ruby 3.3+, our floor is 3.2
gem "pry-byebug", platforms: :mri
gem "rack-test", "~> 2.1"
gem "rake", "~> 13.4"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.90"
gem "rubocop-rake"
gem "rubocop-rspec"
gem "webmock", "~> 3.26"
