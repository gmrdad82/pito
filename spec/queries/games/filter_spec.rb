require "rails_helper"

# Phase 27 v2 spec 06 — Filter row query object.
#
# v2 contract: `checked_tokens` is the SET OF CHECKED chips. Each
# group (status / ownership / platform) narrows when a STRICT SUBSET
# of its chips is checked; all-checked = no narrowing; zero-checked =
# the group collapses to `Game.none`. Cross-group: AND.
#
# Cascade — the query side does NOT enforce the Stimulus `played` →
# `released + owned + at-least-one-platform` cascade. If a URL is
# hand-edited to `?filters=played` (no implied chips), the query
# returns `Game.none` (zero status checks AND zero platform checks
# collapse).
RSpec.describe Games::Filter do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 5, 17, 12, 0, 0) }
  around { |ex| travel_to(now) { ex.run } }

  let(:universe) { Games::Filter::TOKEN_UNIVERSE }

  describe "TOKEN_UNIVERSE" do
    # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `gog` and
    # `epic` chips were retired; PC = Steam everywhere. The universe
    # is now eight canonical tokens.
    it "lists the eight v2 canonical tokens" do
      expect(universe).to eq(%w[
        released scheduled owned wishlist played
        ps5 switch2 steam
      ])
    end

    it "exposes the legacy CANONICAL_TOKENS alias" do
      expect(Games::Filter::CANONICAL_TOKENS).to eq(universe)
    end
  end

  let!(:platform_ps5)     { create(:platform, name: "ps5",     slug: "ps5") }
  let!(:platform_switch2) { create(:platform, name: "switch2", slug: "switch2") }
  let!(:platform_steam)   { create(:platform, name: "steam",   slug: "steam") }

  # Fixture matrix (post PC-store-collapse 2026-05-17):
  #   | Game | Available on | Owned on | Released? | played_at |
  #   | A    | PS5, Switch2 | PS5      | yes       | nil       |
  #   | B    | PS5, Steam   | (none)   | yes       | nil       |
  #   | C    | Switch2      | (none)   | no (sched)| nil       |
  #   | D    | PS5, Switch2 | PS5      | no (sched)| nil       |
  #   | E    | Steam        | Steam    | yes       | 1.day.ago |
  #
  # Games F (GOG-only) and G (Epic-only) from the prior fixture matrix
  # are retired alongside the chips. The "PC umbrella under Steam"
  # coverage shifts onto Game E (Steam-owned + played) and Game B
  # (Steam-available, not owned — exercises the wishlist semantic).
  let(:past)   { 1.year.ago.to_date }
  let(:future) { 1.year.from_now.to_date }

  let!(:game_a) do
    g = create(:game, title: "Game A", release_date: past)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platforms.create!(platform: platform_switch2)
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end
  let!(:game_b) do
    g = create(:game, title: "Game B", release_date: past)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platforms.create!(platform: platform_steam)
    g
  end
  let!(:game_c) do
    g = create(:game, title: "Game C", release_date: future)
    g.game_platforms.create!(platform: platform_switch2)
    g
  end
  let!(:game_d) do
    g = create(:game, title: "Game D", release_date: future)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platforms.create!(platform: platform_switch2)
    g.game_platform_ownerships.create!(platform: platform_ps5)
    g
  end
  let!(:game_e) do
    g = create(:game, title: "Game E", release_date: past, played_at: 1.day.ago)
    g.game_platforms.create!(platform: platform_steam)
    g.game_platform_ownerships.create!(platform: platform_steam)
    g
  end

  def titles_for(tokens)
    Games::Filter.new(scope: Game.all, tokens: tokens).results.order(:title).pluck(:title)
  end

  describe "nil tokens — universe ⇒ full list" do
    it "returns every fixture game" do
      expect(titles_for(nil)).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E])
    end

    it "checked_tokens equals the universe" do
      expect(Games::Filter.new(tokens: nil).checked_tokens).to eq(universe)
    end
  end

  describe "every chip checked (Array == universe) ⇒ full list" do
    it "returns every fixture game" do
      expect(titles_for(universe)).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E])
    end
  end

  describe "empty Array ⇒ Game.none (every group collapses)" do
    it "returns no games" do
      expect(titles_for([])).to eq([])
    end

    it "checked_tokens is empty" do
      expect(Games::Filter.new(tokens: []).checked_tokens).to eq([])
    end
  end

  describe "single status chip checked" do
    it "[released] only — status narrows; ownership + platform empty → none" do
      # Only `released` checked in status; ownership group has zero
      # checks; platform group has zero checks → AND collapses.
      expect(titles_for(%w[released])).to eq([])
    end
  end

  describe "status + ownership + platform groups all narrowed" do
    it "[released, owned, ps5] → released AND owned AND ownable on ps5 (precedence: owned_on)" do
      expect(titles_for(%w[released owned ps5])).to eq([ "Game A" ])
    end

    it "[scheduled, owned, ps5] → scheduled AND owned-on-ps5 → Game D" do
      expect(titles_for(%w[scheduled owned ps5])).to eq([ "Game D" ])
    end

    it "[scheduled, wishlist, switch2] → scheduled AND not-owned AND switch2 → Game C" do
      expect(titles_for(%w[scheduled wishlist switch2])).to eq([ "Game C" ])
    end
  end

  describe "wishlist semantic — NOT owned on ANY platform (orthogonal to release)" do
    # The wishlist group requires the status + platform groups to ALSO
    # have at least one check to avoid the all-collapse. We feed both
    # status chips checked and every platform checked (the same shape
    # the Stimulus controller produces when the user picks wishlist
    # from a freshly checked-all state and only unchecks owned + played).
    let(:tokens_wishlist_widened) do
      %w[released scheduled wishlist ps5 switch2 steam]
    end

    it "includes a released-not-owned game (Game B)" do
      expect(titles_for(tokens_wishlist_widened)).to include("Game B")
    end

    it "includes a scheduled-not-owned game (Game C)" do
      expect(titles_for(tokens_wishlist_widened)).to include("Game C")
    end

    it "excludes owned games (Game A / D / E)" do
      result = titles_for(tokens_wishlist_widened)
      expect(result).not_to include("Game A", "Game D", "Game E")
    end
  end

  describe "played semantic — played_at IS NOT NULL" do
    it "[played alone in ownership, rest of universe checked] returns owned-on-any UNION played" do
      # Status = released+scheduled (all checked, no narrowing).
      # Ownership = played only → played_at non-null = Game E.
      # Platform = all checked, no narrowing.
      # Intersection = Game E.
      tokens = %w[released scheduled played ps5 switch2 steam]
      expect(titles_for(tokens)).to eq([ "Game E" ])
    end

    it "[played] alone (no cascade applied) → Game.none (status + platform collapse)" do
      expect(titles_for(%w[played])).to eq([])
    end

    it "[released, owned, played, all platforms] cascade-shaped state → owned UNION played intersected with released" do
      # Ownership union: owned (A, D, E) ∪ played (E) = A, D, E.
      # Status: released only → A, B, E.
      # Platform: all 3 → no narrowing.
      # Intersection: A, E.
      tokens = %w[released owned played ps5 switch2 steam]
      expect(titles_for(tokens)).to match_array([ "Game A", "Game E" ])
    end
  end

  describe "platform-precedence preserved from 01b §2" do
    let(:tokens_ps5_no_owned) do
      # owned NOT checked → platform narrows via on_platform (released-
      # or-scheduled on PS5, ownership-agnostic).
      %w[released scheduled owned wishlist played ps5]
    end

    it "[no platforms except ps5] (owned still checked) → owned-on-PS5 (A + D)" do
      # owned in checked set → platform branch routes through owned_on.
      tokens = %w[released scheduled owned wishlist played ps5]
      expect(titles_for(tokens)).to match_array([ "Game A", "Game D" ])
    end

    it "[no platforms except ps5] (owned UNCHECKED) → on_platform(ps5) AND (wishlist OR played) → Game B" do
      # owned NOT checked → platform branch routes through on_platform
      # (released-or-scheduled on PS5, ownership-agnostic): A, B, D.
      # Ownership group checked = wishlist + played:
      #   - wishlist (no ownership rows anywhere): B, C, F.
      #   - played   (played_at non-null):         E.
      # Union ownership: B, C, E, F. Intersection with PS5 platform
      # (A, B, D) → B.
      tokens = %w[released scheduled wishlist played ps5]
      expect(titles_for(tokens)).to eq([ "Game B" ])
    end
  end

  describe "platform group OR semantics" do
    it "two platforms checked (with owned) → union of owned-on results" do
      # owned + ps5 + steam → games owned on PS5 OR Steam → A, D, E.
      tokens = %w[released scheduled owned wishlist played ps5 steam]
      expect(titles_for(tokens)).to match_array([ "Game A", "Game D", "Game E" ])
    end
  end

  describe "status group OR semantics" do
    it "all platforms + ownership checked, only `released` in status → only past-release games" do
      tokens = %w[released owned wishlist played ps5 switch2 steam]
      # Released past games — A, B, E.
      expect(titles_for(tokens)).to match_array([ "Game A", "Game B", "Game E" ])
    end

    it "all platforms + ownership checked, only `scheduled` in status → only future-release games" do
      tokens = %w[scheduled owned wishlist played ps5 switch2 steam]
      # Scheduled future games — C, D.
      expect(titles_for(tokens)).to match_array([ "Game C", "Game D" ])
    end
  end

  describe "input normalisation" do
    it "case-insensitive (PS5 → ps5)" do
      expect(titles_for([ "PS5" ])).to eq(titles_for([ "ps5" ]))
    end

    it "trims whitespace ('  ps5 ')" do
      expect(titles_for([ " ps5 " ])).to eq(titles_for([ "ps5" ]))
    end

    it "dedupes (ps5, ps5)" do
      expect(titles_for(%w[ps5 ps5])).to eq(titles_for(%w[ps5]))
    end

    it "drops unknowns (bogus, ps5 → ps5)" do
      expect(titles_for(%w[bogus ps5])).to eq(titles_for(%w[ps5]))
    end

    it "input order does not affect the result set" do
      a = titles_for(%w[owned ps5 released])
      b = titles_for(%w[released ps5 owned])
      expect(a).to eq(b)
    end
  end

  describe "#dropped_tokens" do
    it "lists unknown tokens for a non-nil input" do
      filter = Games::Filter.new(tokens: %w[ps5 bogus xbox gog epic])
      # Bogus, the legacy xbox token, and the now-retired gog + epic
      # tokens (collapsed into steam 2026-05-17) all fall outside the
      # v2 universe.
      expect(filter.dropped_tokens).to match_array(%w[bogus xbox gog epic])
    end

    it "is empty for nil input (universe is implicit)" do
      expect(Games::Filter.new(tokens: nil).dropped_tokens).to eq([])
    end
  end

  describe "#contradiction? — always false in v2" do
    it "returns false even when fed legacy contradiction inputs" do
      filter = Games::Filter.new(tokens: %w[owned not_owned])
      expect(filter.contradiction?).to be(false)
    end
  end

  describe "defensive surface" do
    it "100-token bogus CSV does not blow up; falls back to empty checked set" do
      tokens = Array.new(100) { |i| "bogus-#{i}" }
      filter = Games::Filter.new(scope: Game.all, tokens: tokens)
      expect(filter.checked_tokens).to eq([])
      expect(filter.results.to_a).to eq([])
    end

    it "SQL-injection-shaped token is dropped" do
      payload = "ps5'; DROP TABLE games; --"
      filter = Games::Filter.new(scope: Game.all, tokens: [ payload ])
      expect(filter.dropped_tokens).to include(payload.downcase)
      expect(filter.checked_tokens).to eq([])
      expect(Game.table_exists?).to be(true)
    end

    it "#results returns an ActiveRecord::Relation (composable)" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps5])
      expect(filter.results).to be_a(ActiveRecord::Relation)
    end

    it "#results is memoised" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps5])
      expect(filter.results.to_sql).to eq(filter.results.to_sql)
    end
  end
end
