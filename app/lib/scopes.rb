# Single source of truth for token scopes across the entire stack. One
# scope:
#
#   - `app` — application data — channels, videos, projects, calendar, etc.
#
# `Scopes::ALL` is a frozen array captured at boot. Doorkeeper's
# initializer reads the constant directly because initializers can run
# before the autoloader is fully wired.
module Scopes
  APP = "app"

  DESCRIPTIONS = {
    APP => "application access. manage channels, videos, projects, and the calendar."
  }.freeze

  # The catalog. One entry today; the method form remains for callers
  # that pre-date the simplification and for forward compatibility if a
  # future scope is reintroduced.
  def self.all
    [ APP ].freeze
  end

  # Frozen array captured at boot. Doorkeeper's initializer reads this
  # constant directly because initializers can run before the
  # autoloader is fully wired.
  ALL = all
end
