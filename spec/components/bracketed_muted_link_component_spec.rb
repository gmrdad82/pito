# frozen_string_literal: true

# PLACEHOLDER SPEC — fill in before the next CI run.
#
# This file uses `pending` blocks so the suite stays loadable and the missing
# coverage shows up in the RSpec report without failing the build. Replace
# each `pending` with a real example following the project's
# `feedback_spec_exhaustively` expectation:
#
#   - unit       — initializer / readers / helper methods (e.g. `html_data`)
#   - render     — default markup (bracketed `[<span class="bl">label</span>]`,
#                  `a.bracketed.bracketed-muted-link` wrapper)
#   - variants   — custom `label:` (cancel / help / discard / go back / close
#                  / a Git SHA), `method:` (turbo_method data attr), `data:`
#                  merge, `target:`, `rel:`
#   - edges      — nil `method`, empty `data` hash, label override falls back
#                  to "cancel"
#   - a11y       — link role, visible bracket text, hover/rest color contract
#                  documented in the component header
#
# Sibling reference: spec/components/bracketed_link_component_spec.rb.
#
# Renamed from BracketedCancelComponent (2026-05) once a second consumer
# (the `[help]` link on the Slack + Discord webhook panes) and a third
# (the footer version SHA link) made the "Cancel" name read misleading.
# The visual contract is "muted secondary bracketed link with hover-lift".

require "rails_helper"

RSpec.describe BracketedMutedLinkComponent, type: :component do
  describe "unit" do
    pending "exposes html_data merging :turbo_method when method: is provided"
    pending "returns @data unchanged when method: is nil"
    pending "defaults label to 'cancel' when not supplied"
  end

  describe "render" do
    pending "renders a link with bracketed + bracketed-muted-link classes"
    pending "wraps the label in [<span class='bl'>...</span>] markup"
    pending "uses the provided href on the anchor"
  end

  describe "variants" do
    pending "renders a custom label (e.g. 'help', 'discard', 'go back', 'close')"
    pending "emits data-turbo-method when method: :delete is passed"

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

    pending "passes target: through to the anchor"
    pending "passes rel: through to the anchor"
  end

  describe "edges" do
    pending "omits data-turbo-method when method: is nil"
    pending "renders with no data attributes when data: is empty"
  end

  describe "a11y" do
    pending "is reachable as a link (role=link via <a href>)"
    pending "keeps bracket characters visible in the accessible name"
  end
end
