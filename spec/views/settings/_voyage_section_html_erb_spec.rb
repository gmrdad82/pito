require "rails_helper"

# Phase 32 follow-up (2026-05-16) — Voyage section of the Stack pane,
# extracted so `ReindexAllJob` can Turbo-Stream-replace it without
# re-rendering the entire pane. Renders one of two states gated on
# `AppSetting.reindex_running?`:
#
#   * idle    — `[reindex]` destructive bracketed link + confirm modal.
#   * running — `.dot-loader` `=/-` indicator + "reindexing... started
#               ~Xs ago" line.
#
# Both states wrap in a `<div id="voyage_section">` so the broadcast
# target string stays stable.
RSpec.describe "settings/_voyage_section.html.erb", type: :view do
  describe "idle state (no reindex running)" do
    it "wraps the section in `<div id=\"voyage_section\">` " \
       "(the broadcast target)" do
      pending "validated manually first; spec fills in after the operator " \
              "confirms the partial renders both states correctly"
      raise "pending placeholder"
    end

    it "renders the `[reindex]` destructive bracketed link wired to " \
       "the confirm modal" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "does NOT render the dot-loader indicator" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "running state (reindex in progress)" do
    it "wraps the section in `<div id=\"voyage_section\">`" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "renders the `.dot-loader` `=/-` indicator" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "renders the 'reindexing... started ~Xs ago' line via " \
       "compact_time_ago(AppSetting.reindex_started_at)" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "does NOT render the `[reindex]` bracketed link" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end

  describe "Voyage credentials gating" do
    it "shows the configured indicator when " \
       "AppSetting.voyage_configured? is true" do
      pending "validated manually first"
      raise "pending placeholder"
    end

    it "shows the not-configured indicator when " \
       "AppSetting.voyage_configured? is false" do
      pending "validated manually first"
      raise "pending placeholder"
    end
  end
end
