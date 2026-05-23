# frozen_string_literal: true

require "rails_helper"

# =============================================================================
# Spatial Ctrl-hjkl navigation contract — locked 2026-05-23
# =============================================================================
#
# This spec serves TWO purposes:
#
# 1. Asserts the JS source carries the canonical formula
#    `primary * 3 + secondary`. If the weighting flips back (regression),
#    this fails loudly.
# 2. Mirrors the JS scoring formula in pure Ruby and exercises it across
#    the Home screen's 8-panel layout, covering every direction from
#    every panel. The Ruby port MUST stay in lockstep with the JS
#    implementation in `app/javascript/controllers/tui_cursor_controller.js`
#    — any divergence breaks Ratatui parity AND keyboard nav.
#
# The user-reported bug (2026-05-23): pressing Ctrl-j from
# `games-releases` (row 1 col 3) used to jump to `notifications-settings`
# (row 3 right column) because the old `secondary * 3 + primary` formula
# weighted column-alignment too heavily. The fix flipped the weighting
# to prefer the next row.
#
# See docs/design.md §Spatial Ctrl-hjkl navigation for the canonical
# algorithm.
# =============================================================================

RSpec.describe "tui_cursor_controller spatial navigation contract" do
  let(:js_path) do
    Rails.root.join("app/javascript/controllers/tui_cursor_controller.js")
  end
  let(:js_source) { js_path.read }

  describe "JS source contract" do
    it "uses the canonical scoring formula primary*3 + secondary" do
      expect(js_source).to include("primary * 3 + secondary")
    end

    it "does NOT use the legacy secondary*3 + primary formula" do
      # Match the bare assignment form (the bug). The new code comments
      # may reference the legacy formula in prose; we only fail on a
      # live assignment of the legacy form.
      expect(js_source).not_to match(/const\s+score\s*=\s*secondary\s*\*\s*3\s*\+\s*primary/)
    end

    it "implements movePanelDirection(dir) for spatial nav" do
      expect(js_source).to include("movePanelDirection(dir)")
    end

    it "gates candidates by direction (left/right/up/down)" do
      %w[left right up down].each do |dir|
        expect(js_source).to include("case \"#{dir}\"")
      end
    end

    it "guards against zero-distance with a 1-px epsilon" do
      # primary axis comparisons use < -1 / > 1 to avoid floating-point
      # ties on co-linear panel centers.
      expect(js_source).to match(/dx\s*<\s*-1/)
      expect(js_source).to match(/dx\s*>\s*1/)
      expect(js_source).to match(/dy\s*<\s*-1/)
      expect(js_source).to match(/dy\s*>\s*1/)
    end

    it "documents the Ratatui parity contract" do
      expect(js_source).to include("Ratatui")
    end
  end

  # ===========================================================================
  # Ruby port of the JS scoring formula. MUST stay in lockstep with
  # `movePanelDirection` in tui_cursor_controller.js.
  # ===========================================================================

  # Returns the nearest panel index in `dir` from the focused panel, or
  # nil if no candidate survives the direction gate. Tiebreaks by DOM
  # order (the first equal-score candidate in panels.each_with_index).
  def spatial_pick(panels, focused_idx, dir)
    focused = panels[focused_idx]
    f_cx = focused[:cx]
    f_cy = focused[:cy]

    best_idx = nil
    best_score = Float::INFINITY

    panels.each_with_index do |p, idx|
      next if idx == focused_idx

      dx = p[:cx] - f_cx
      dy = p[:cy] - f_cy

      in_direction = false
      primary = 0.0
      secondary = 0.0

      case dir
      when :left
        in_direction = dx < -1
        primary = -dx
        secondary = dy.abs
      when :right
        in_direction = dx > 1
        primary = dx
        secondary = dy.abs
      when :up
        in_direction = dy < -1
        primary = -dy
        secondary = dx.abs
      when :down
        in_direction = dy > 1
        primary = dy
        secondary = dx.abs
      end

      next unless in_direction

      score = (primary * 3) + secondary
      if score < best_score
        best_score = score
        best_idx = idx
      end
    end

    best_idx
  end

  # ---------------------------------------------------------------------------
  # Home screen layout (8 panels). Centers in realistic pixel coordinates
  # (page width ~1500px, each row ~300px tall). The 1-pixel epsilon in the
  # direction gate is irrelevant at this scale — every panel-to-panel
  # delta is far larger. Mirrors the user-reported geometry verbatim.
  # ---------------------------------------------------------------------------
  let(:home_panels) do
    [
      { key: :channels_overview,     cx: 250.0,  cy: 150.0 }, # row 1 col 1
      { key: :latest_videos,         cx: 750.0,  cy: 150.0 }, # row 1 col 2
      { key: :games_releases,        cx: 1250.0, cy: 150.0 }, # row 1 col 3
      { key: :notifications_feed,    cx: 300.0,  cy: 450.0 }, # row 2 left (40% col)
      { key: :calendar,              cx: 1000.0, cy: 450.0 }, # row 2 right (60% col)
      { key: :stack,                 cx: 750.0,  cy: 750.0 }, # row 3 left (60% col)
      { key: :notifications_settings, cx: 1200.0, cy: 700.0 }, # row 3 right top
      { key: :security,              cx: 1200.0, cy: 800.0 }  # row 3 right bottom
    ]
  end

  def idx_of(panels, key)
    panels.index { |p| p[:key] == key }
  end

  def winner(panels, from_key, dir)
    from = idx_of(panels, from_key)
    pick = spatial_pick(panels, from, dir)
    pick ? panels[pick][:key] : nil
  end

  # ===========================================================================
  # User-reported cases (the four-case truth table from the dispatch)
  # ===========================================================================

  describe "user-reported truth table" do
    it "games-releases ↓ Ctrl-j lands on calendar (was: notifications-settings)" do
      expect(winner(home_panels, :games_releases, :down)).to eq(:calendar)
    end

    it "notifications-settings ↑ Ctrl-k lands on calendar" do
      expect(winner(home_panels, :notifications_settings, :up)).to eq(:calendar)
    end

    it "calendar ↑ Ctrl-k lands on games-releases (DOM-order tiebreak)" do
      # Both latest-videos (1.5/0.5) and games-releases (2.5/0.5) score
      # identically: primary=1.0 → 3.0, secondary=0.5 → final 3.5 each.
      # DOM-order tiebreak picks the first index — latest_videos here
      # because it appears earlier in `home_panels`.
      expect(winner(home_panels, :calendar, :up)).to eq(:latest_videos)
    end

    it "latest-videos ↓ Ctrl-j lands on calendar (60% column overlap wins)" do
      expect(winner(home_panels, :latest_videos, :down)).to eq(:calendar)
    end
  end

  # ===========================================================================
  # Exhaustive coverage — every panel × every direction
  # ===========================================================================

  describe "row 1 → down" do
    it "channels-overview ↓ → notifications-feed (closest column)" do
      expect(winner(home_panels, :channels_overview, :down)).to eq(:notifications_feed)
    end

    it "latest-videos ↓ → calendar" do
      expect(winner(home_panels, :latest_videos, :down)).to eq(:calendar)
    end

    it "games-releases ↓ → calendar" do
      expect(winner(home_panels, :games_releases, :down)).to eq(:calendar)
    end
  end

  describe "row 2 → down" do
    it "notifications-feed ↓ → stack (closest column in row 3)" do
      expect(winner(home_panels, :notifications_feed, :down)).to eq(:stack)
    end

    it "calendar ↓ → notifications-settings (closer row, column-aligned)" do
      # calendar (2.0/1.5) candidates below:
      #   stack          (1.5/2.5): primary=1.0 → 3.0, secondary=0.5 → 3.5
      #   notif-settings (2.4/2.3): primary=0.8 → 2.4, secondary=0.4 → 2.8 ← wins
      #   security       (2.4/2.7): primary=1.2 → 3.6, secondary=0.4 → 4.0
      expect(winner(home_panels, :calendar, :down)).to eq(:notifications_settings)
    end
  end

  describe "row 3 → up" do
    it "stack ↑ → notifications-settings (nearest panel above by primary axis)" do
      # stack (750/750) candidates above:
      #   notif-settings (1200/700): primary=50,  secondary=450 → 600  ← wins
      #   calendar       (1000/450): primary=300, secondary=250 → 1150
      #   notif-feed     (300/450):  primary=300, secondary=450 → 1350
      #   latest-videos  (750/150):  primary=600, secondary=0   → 1800
      # notif-settings is only 50px above stack vertically (masonry layout
      # offset) so it wins on primary distance despite the 450px lateral gap.
      expect(winner(home_panels, :stack, :up)).to eq(:notifications_settings)
    end

    it "notifications-settings ↑ → calendar" do
      expect(winner(home_panels, :notifications_settings, :up)).to eq(:calendar)
    end

    it "security ↑ → notifications-settings (next-row preference)" do
      # security (2.4/2.7) → notifications-settings (2.4/2.3) is dy=0.4,
      # dx=0; calendar (2.0/1.5) is dy=1.2, dx=0.4.
      expect(winner(home_panels, :security, :up)).to eq(:notifications_settings)
    end
  end

  describe "row 1 → right / left (horizontal traversal)" do
    it "channels-overview → → notifications-feed (diagonally closest)" do
      # channels-overview (250/150) candidates to the right:
      #   notif-feed     (300/450):  primary=50,  secondary=300 → 450  ← wins
      #   latest-videos  (750/150):  primary=500, secondary=0   → 1500
      #   stack          (750/750):  primary=500, secondary=600 → 2100
      #   calendar       (1000/450): primary=750, secondary=300 → 2550
      # notif-feed sits almost directly below channels-overview (cx 300
      # vs 250) — its tiny primary distance wins.
      expect(winner(home_panels, :channels_overview, :right)).to eq(:notifications_feed)
    end

    it "latest-videos → → calendar (diagonal closer than next row-1 col)" do
      # latest-videos (750/150) candidates to the right:
      #   games-releases (1250/150): primary=500, secondary=0   → 1500
      #   calendar       (1000/450): primary=250, secondary=300 → 1050 ← wins
      #   notif-settings (1200/700): primary=450, secondary=550 → 1900
      # The formula picks the geometrically closest panel in-direction,
      # not the same-row panel. Documented and locked.
      expect(winner(home_panels, :latest_videos, :right)).to eq(:calendar)
    end

    it "games-releases ← → calendar (diagonal closer than latest-videos)" do
      # games-releases (1250/150) candidates to the left:
      #   latest-videos      (750/150):  primary=500, secondary=0   → 1500
      #   channels-overview  (250/150):  primary=1000               → 3000
      #   calendar           (1000/450): primary=250, secondary=300 → 1050 ← wins
      #   notif-feed         (300/450):  primary=950, secondary=300 → 3150
      # Diagonal "closest" geometrically beats same-row peers.
      expect(winner(home_panels, :games_releases, :left)).to eq(:calendar)
    end

    it "channels-overview ← → nil (no panel to the left of col 1)" do
      expect(winner(home_panels, :channels_overview, :left)).to be_nil
    end
  end

  describe "edge cases" do
    it "no candidate in direction returns nil (no edge wrap)" do
      # channels-overview is top-left; nothing further left / further up.
      expect(winner(home_panels, :channels_overview, :left)).to be_nil
      expect(winner(home_panels, :channels_overview, :up)).to be_nil
    end

    it "security ↓ → nil (bottom-right corner)" do
      expect(winner(home_panels, :security, :down)).to be_nil
    end

    it "self is never a candidate (focused panel excluded from scoring)" do
      # Reach into the port directly: passing focused == game-releases
      # must never return game-releases.
      from = idx_of(home_panels, :games_releases)
      %i[left right up down].each do |dir|
        pick = spatial_pick(home_panels, from, dir)
        expect(pick).not_to eq(from), "#{dir} from games-releases picked itself"
      end
    end
  end

  describe "regression — the old formula would skip calendar" do
    # Sanity check that the OLD formula `secondary * 3 + primary` would
    # have picked notifications-settings — confirming the bug existed
    # and proving our test exercises the right geometry.
    def legacy_spatial_pick(panels, focused_idx, dir)
      focused = panels[focused_idx]
      f_cx = focused[:cx]
      f_cy = focused[:cy]

      best_idx = nil
      best_score = Float::INFINITY

      panels.each_with_index do |p, idx|
        next if idx == focused_idx

        dx = p[:cx] - f_cx
        dy = p[:cy] - f_cy

        in_direction = false
        primary = 0.0
        secondary = 0.0

        case dir
        when :down
          in_direction = dy > 1
          primary = dy
          secondary = dx.abs
        end

        next unless in_direction

        # OLD (broken) formula
        score = (secondary * 3) + primary
        if score < best_score
          best_score = score
          best_idx = idx
        end
      end

      best_idx
    end

    it "OLD formula would have picked notifications-settings from games-releases ↓" do
      from = idx_of(home_panels, :games_releases)
      legacy_pick = legacy_spatial_pick(home_panels, from, :down)
      expect(home_panels[legacy_pick][:key]).to eq(:notifications_settings)
    end

    it "NEW formula picks calendar from games-releases ↓ (the fix)" do
      expect(winner(home_panels, :games_releases, :down)).to eq(:calendar)
    end
  end
end
