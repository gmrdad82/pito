# frozen_string_literal: true

# RSpec support hook for Pito::Copy.
#
# By default the copy engine picks a random variant (entries.sample).  That
# makes specs non-deterministic.  This hook installs a deterministic sampler
# (always the FIRST entry) before the suite runs, and restores the default
# random sampler after each example so any per-example override is isolated.
#
# Per-example override — pick last entry:
#   before { Pito::Copy.sampler = ->(e) { e.last } }
#
# Per-call override — force a specific index:
#   Pito::Copy.render("some.key", variant: 2)

RSpec.configure do |config|
  # Install the deterministic (first-entry) sampler for the entire test suite.
  config.before(:suite) do
    Pito::Copy.sampler = ->(entries) { entries.first }
  end

  # Restore the default sampler after every example so per-example overrides
  # (e.g. setting Pito::Copy.sampler = ... in a before block) don't bleed.
  config.after(:each) do
    Pito::Copy.reset_sampler!
    # Re-install the deterministic sampler for the next example.
    Pito::Copy.sampler = ->(entries) { entries.first }
  end
end
