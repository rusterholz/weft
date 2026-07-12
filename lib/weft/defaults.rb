# frozen_string_literal: true

# Weft::Defaults namespace — gem-provided Page/Component classes used as
# fallback targets when no user-declared recovers entry matches. Pointed at
# by Weft::Configuration#error_component / #error_page / #not_found_page.
require "weft/defaults/error_component"
require "weft/defaults/error_page"
require "weft/defaults/not_found_component"
require "weft/defaults/not_found_page"
