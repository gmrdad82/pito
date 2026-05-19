# frozen_string_literal: true

# Renamed from BracketedCancelComponent (2026-05) once a second consumer
# (the `[help]` link on the Slack + Discord webhook panes) and a third
# (the footer version SHA link) made the "Cancel" name read misleading.
# The visual contract is "muted secondary bracketed link with hover-lift".

require "rails_helper"

RSpec.describe BracketedMutedLinkComponent, type: :component do
  describe "variants" do
    # Phase 27 spec 04 (2026-05-17) — the IGDB add-game modal's
    # `[cancel]` link relies on `data:` passthrough to wire the
    # Stimulus `click->igdb-search-modal#close` action onto the
    # anchor. Lock the behavior so a future refactor cannot drop
    # it silently.
    it "merges arbitrary data: attributes onto the anchor" do
      render_inline(
        described_class.new(
          href: "#",
          data: { action: "click->igdb-search-modal#close" }
        )
      )
      expect(page).to have_css(
        'a.bracketed.bracketed-muted-link[data-action="click->igdb-search-modal#close"]'
      )
    end
  end
end
