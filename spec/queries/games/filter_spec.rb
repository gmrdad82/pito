require "rails_helper"

# Games::Filter — locked semantics per ADR 0013 (2026-05-17). Four
# orthogonal axes combined with within-axis OR and cross-axis AND.
# Chip vocabulary collapses console + PC families into a single user-
# facing token:
#   - `ps`     → DB slugs `ps5` + `ps4--1`
#   - `switch` → DB slugs `switch` + `switch-2`
#   - `steam`  → DB slugs `win` + `linux` + `mac` + `dos` + `web` + `steam`
#
# The query side is the only enforcer of the axis combinators; the
# Stimulus UI is the only enforcer of the conditional `played` cascade
# (`played` implies `released + owned + at-least-one-platform`).
# Hand-edited URLs (e.g. `?filters=played`) hit the query directly and
# pass through without cascade enforcement.
RSpec.describe Games::Filter do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 5, 18, 12, 0, 0) }
  around { |ex| travel_to(now) { ex.run } }

  let(:universe) { Games::Filter::TOKEN_UNIVERSE }

  describe "constants — single source for the chip vocabulary" do
    it "lists the eight v3 canonical tokens in render order" do
      expect(universe).to eq(%w[
        released scheduled owned wishlist played ps switch steam
      ])
    end

    it "exposes the legacy CANONICAL_TOKENS alias" do
      expect(Games::Filter::CANONICAL_TOKENS).to eq(universe)
    end

    it "exposes the LIFECYCLE_TOKENS / OWNERSHIP_TOKENS / ENGAGEMENT_TOKENS / PLATFORM_TOKENS axes" do
      expect(Games::Filter::LIFECYCLE_TOKENS).to  eq(%w[released scheduled])
      expect(Games::Filter::OWNERSHIP_TOKENS).to  eq(%w[owned wishlist])
      expect(Games::Filter::ENGAGEMENT_TOKENS).to eq(%w[played])
      expect(Games::Filter::PLATFORM_TOKENS).to   eq(%w[ps switch steam])
    end

    it "STATUS_TOKENS aliases LIFECYCLE_TOKENS for legacy callers" do
      expect(Games::Filter::STATUS_TOKENS).to eq(Games::Filter::LIFECYCLE_TOKENS)
    end

    it "TOKEN_TO_PLATFORM_SLUGS maps each chip to its DB slug family" do
      map = Games::Filter::TOKEN_TO_PLATFORM_SLUGS
      expect(map["ps"]).to     eq(%w[ps5 ps4--1])
      expect(map["switch"]).to eq(%w[switch switch-2])
      expect(map["steam"]).to  eq(%w[win linux mac dos web steam])
    end

    it "DEFAULT_CHECKED_TOKENS is the universe minus the `played` engagement chip" do
      expect(Games::Filter::DEFAULT_CHECKED_TOKENS).to eq(universe - %w[played])
    end
  end

  # ----------------------------------------------------------------
  # Fixture matrix — one platform row per DB slug per chip family, to
  # exercise the chip-to-family expansion behaviour.
  #
  # | Game | Available on            | Owned on  | Released? | played_at |
  # | A    | ps5, switch             | ps5       | yes       | nil       |
  # | B    | ps5, steam              | (none)    | yes       | nil       |
  # | C    | switch-2                | (none)    | no (sched)| nil       |
  # | D    | ps4--1, switch-2        | ps4--1    | no (sched)| nil       |
  # | E    | steam                   | steam     | yes       | 1.day.ago |
  # | F    | win                     | win       | yes       | nil       |
  # ----------------------------------------------------------------

  # Platforms — slugs MUST match `TOKEN_TO_PLATFORM_SLUGS` exactly
  # (`ps` → `ps5` / `ps4--1`, `switch` → `switch` / `switch-2`, `steam`
  # → `win` / `linux` / `mac` / `dos` / `web` / `steam`). FriendlyId
  # auto-derives the slug from `name` and clobbers any `slug:` passed
  # to the factory; we use `update_column(:slug, ...)` after create to
  # bypass the FriendlyId callback so the desired slug sticks.
  def make_platform(slug:, igdb_id:)
    p = create(:platform, name: slug, igdb_id: igdb_id)
    p.update_column(:slug, slug)
    p
  end

  let!(:platform_ps5)     { make_platform(slug: "ps5",      igdb_id: 167) }
  let!(:platform_ps4)     { make_platform(slug: "ps4--1",   igdb_id: 48) }
  let!(:platform_switch)  { make_platform(slug: "switch",   igdb_id: 130) }
  let!(:platform_switch2) { make_platform(slug: "switch-2", igdb_id: 508) }
  let!(:platform_steam)   { make_platform(slug: "steam",    igdb_id: 6) }
  let!(:platform_win)     { make_platform(slug: "win",      igdb_id: 7) }

  let(:past)   { 1.year.ago.to_date }
  let(:future) { 1.year.from_now.to_date }

  let!(:game_a) do
    g = create(:game, title: "Game A", release_date: past)
    g.game_platforms.create!(platform: platform_ps5)
    g.game_platforms.create!(platform: platform_switch)
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
    g.game_platforms.create!(platform: platform_ps4)
    g.game_platforms.create!(platform: platform_switch2)
    g.game_platform_ownerships.create!(platform: platform_ps4)
    g
  end

  let!(:game_e) do
    g = create(:game, title: "Game E", release_date: past, played_at: 1.day.ago)
    g.game_platforms.create!(platform: platform_steam)
    g.game_platform_ownerships.create!(platform: platform_steam)
    g
  end

  let!(:game_f) do
    g = create(:game, title: "Game F", release_date: past)
    g.game_platforms.create!(platform: platform_win)
    g.game_platform_ownerships.create!(platform: platform_win)
    g
  end

  def titles_for(tokens)
    Games::Filter.new(scope: Game.all, tokens: tokens).results.order(:title).pluck(:title)
  end

  # ----------------------------------------------------------------
  # Empty / nil / universe inputs.
  # ----------------------------------------------------------------

  describe "nil tokens → DEFAULT_CHECKED_TOKENS (universe minus `played`)" do
    it "checked_tokens equals the universe minus the engagement axis" do
      expect(Games::Filter.new(tokens: nil).checked_tokens).to eq(universe - %w[played])
    end

    it "returns every fixture game (no engagement narrowing without `played`)" do
      expect(titles_for(nil)).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F])
    end
  end

  describe "explicit empty Array → Game.none" do
    it "returns no games" do
      expect(titles_for([])).to eq([])
    end

    it "checked_tokens is empty" do
      expect(Games::Filter.new(tokens: []).checked_tokens).to eq([])
    end
  end

  describe "every chip explicitly checked → engagement axis still narrows" do
    # The engagement axis is single-chip; checking it always narrows to
    # `played_at IS NOT NULL`. Lifecycle / ownership / platform axes all
    # collapse to "no narrowing" when fully checked, so the only chip
    # that still bites in the universe-checked case is `played`. Only
    # Game E has a non-nil `played_at`.
    it "narrows to played games (Game E) because the played chip is single-chip" do
      expect(titles_for(universe)).to eq([ "Game E" ])
    end
  end

  # ----------------------------------------------------------------
  # AXIS 1: Lifecycle — within-axis OR, axis inactive when both checked.
  # ----------------------------------------------------------------

  describe "lifecycle axis (within-axis OR)" do
    it "[released] only narrows to past-release games" do
      expect(titles_for(%w[released])).to match_array(%w[Game\ A Game\ B Game\ E Game\ F])
    end

    it "[scheduled] only narrows to future-release games" do
      expect(titles_for(%w[scheduled])).to match_array(%w[Game\ C Game\ D])
    end

    it "[released, scheduled] both checked → axis inactive (every game passes)" do
      expect(titles_for(%w[released scheduled])).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F])
    end
  end

  # ----------------------------------------------------------------
  # AXIS 2: Ownership — within-axis OR; both checked + no platform =
  # axis inactive; both checked + a platform set = per-platform union.
  # ----------------------------------------------------------------

  describe "ownership axis" do
    it "[owned] alone narrows to games with at least one ownership row" do
      expect(titles_for(%w[owned])).to match_array(%w[Game\ A Game\ D Game\ E Game\ F])
    end

    it "[wishlist] alone narrows to games with zero ownership rows globally" do
      expect(titles_for(%w[wishlist])).to match_array(%w[Game\ B Game\ C])
    end

    it "[owned, wishlist] with no platform → axis inactive (rule f)" do
      expect(titles_for(%w[owned wishlist])).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F])
    end

    it "[owned, wishlist] with platform=ps → owned-on-ps UNION not-owned-globally on ps" do
      # owned-on-ps: A (ps5), D (ps4--1).
      # not-owned-globally + available on ps: B (ps5, not owned anywhere).
      expect(titles_for(%w[owned wishlist ps])).to match_array(%w[Game\ A Game\ B Game\ D])
    end

    it "[wishlist] is always global (ignores platform availability binding direction)" do
      # wishlist alone (no platform) → not-owned-globally, ignoring
      # release status.
      expect(titles_for(%w[wishlist])).to match_array(%w[Game\ B Game\ C])
    end
  end

  # ----------------------------------------------------------------
  # AXIS 4: Platform — within-axis OR; axis inactive when all 3 checked.
  # ----------------------------------------------------------------

  describe "platform axis (within-axis OR + chip → family expansion)" do
    it "[ps] alone narrows to availability on ps5 OR ps4--1" do
      # A (ps5), B (ps5), D (ps4--1) are available on the ps family.
      expect(titles_for(%w[ps])).to match_array(%w[Game\ A Game\ B Game\ D])
    end

    it "[switch] alone narrows to availability on switch OR switch-2" do
      # A (switch), C (switch-2), D (switch-2).
      expect(titles_for(%w[switch])).to match_array(%w[Game\ A Game\ C Game\ D])
    end

    it "[steam] alone narrows to the PC family (win/linux/mac/dos/web/steam)" do
      # B (steam), E (steam), F (win).
      expect(titles_for(%w[steam])).to match_array(%w[Game\ B Game\ E Game\ F])
    end

    it "[ps, switch] checked → union of both families" do
      # ps: A, B, D. switch: A, C, D. Union: A, B, C, D.
      expect(titles_for(%w[ps switch])).to match_array(%w[Game\ A Game\ B Game\ C Game\ D])
    end

    it "[ps, switch, steam] (all 3 checked) → axis inactive (no narrowing)" do
      expect(titles_for(%w[ps switch steam])).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F])
    end
  end

  # ----------------------------------------------------------------
  # AXIS 3: Engagement — single chip; binds to per-platform when set.
  # ----------------------------------------------------------------

  describe "engagement axis (played)" do
    it "[played] alone → played_at IS NOT NULL (Game E only — cascade not enforced)" do
      expect(titles_for(%w[played])).to eq([ "Game E" ])
    end

    it "[played, ps] → played AND played_platform binds to ps family (none) → empty" do
      # No fixture row has played_platform_id set to a PS platform.
      expect(titles_for(%w[played ps])).to eq([])
    end

    it "[played, steam] → played AND played_platform_id in steam family → still Game E if pointer set" do
      # Set played_platform_id explicitly for Game E to verify binding.
      game_e.update!(played_platform_id: platform_steam.id)
      expect(titles_for(%w[played steam])).to eq([ "Game E" ])
    end
  end

  # ----------------------------------------------------------------
  # Cross-axis AND.
  # ----------------------------------------------------------------

  describe "cross-axis AND" do
    it "[released, owned, ps] → released AND owned-on-ps → Game A only" do
      # released: A, B, E, F. owned: A, D, E, F. ps family availability
      # filter does not apply directly because owned binds to owned_on
      # in the platform branch.
      expect(titles_for(%w[released owned ps])).to eq([ "Game A" ])
    end

    it "[scheduled, owned, ps] → scheduled AND owned-on-ps → Game D only" do
      expect(titles_for(%w[scheduled owned ps])).to eq([ "Game D" ])
    end

    it "[scheduled, wishlist, switch] → scheduled AND not-owned AND switch family → Game C" do
      expect(titles_for(%w[scheduled wishlist switch])).to eq([ "Game C" ])
    end

    it "[released, owned, steam] → released AND owned-on-steam family → Game E + Game F" do
      expect(titles_for(%w[released owned steam])).to match_array(%w[Game\ E Game\ F])
    end
  end

  # ----------------------------------------------------------------
  # Conditional cascade (per project_games_filter_semantics) — the
  # filter itself does NOT enforce. Hand-edited URLs land here.
  # ----------------------------------------------------------------

  describe "conditional cascade — query side does not enforce" do
    it "[played] alone returns played games even though UI requires released + owned + platform" do
      expect(titles_for(%w[played])).to eq([ "Game E" ])
    end

    it "[released, owned, played, ps, switch, steam] cascade-shaped state → released ∩ owned ∩ played" do
      # released ∩ owned ∩ played → E.
      tokens = %w[released owned played ps switch steam]
      expect(titles_for(tokens)).to eq([ "Game E" ])
    end
  end

  # ----------------------------------------------------------------
  # Bundle filtering — sanity check that the filter composes with a
  # pre-scoped relation (e.g. a controller passes `Game.where(id:
  # BundleMember.where(bundle_id: x).select(:game_id))`).
  # ----------------------------------------------------------------

  describe "scope composition" do
    it "filters within a pre-scoped relation rather than the global Game.all" do
      pre_scope = Game.where(id: [ game_a.id, game_d.id ])
      filter = Games::Filter.new(scope: pre_scope, tokens: %w[owned ps])
      expect(filter.results.pluck(:title)).to match_array(%w[Game\ A Game\ D])
    end

    it "#results returns an ActiveRecord::Relation (composable)" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps])
      expect(filter.results).to be_a(ActiveRecord::Relation)
    end

    it "#results is memoised" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps])
      expect(filter.results.to_sql).to eq(filter.results.to_sql)
    end
  end

  # ----------------------------------------------------------------
  # Input normalisation + defensive surface.
  # ----------------------------------------------------------------

  describe "input normalisation" do
    it "case-insensitive (PS → ps)" do
      expect(titles_for(%w[PS])).to eq(titles_for(%w[ps]))
    end

    it "trims whitespace" do
      expect(titles_for([ " ps " ])).to eq(titles_for(%w[ps]))
    end

    it "dedupes (ps, ps)" do
      expect(titles_for(%w[ps ps])).to eq(titles_for(%w[ps]))
    end

    it "drops unknown tokens silently" do
      expect(titles_for(%w[bogus ps])).to eq(titles_for(%w[ps]))
    end

    it "input order does not affect the result set" do
      a = titles_for(%w[owned ps released])
      b = titles_for(%w[released ps owned])
      expect(a).to eq(b)
    end
  end

  describe "#dropped_tokens" do
    it "lists unrecognised tokens for a non-nil input" do
      filter = Games::Filter.new(tokens: %w[ps bogus xbox gog epic])
      expect(filter.dropped_tokens).to match_array(%w[bogus xbox gog epic])
    end

    it "is empty for nil input (universe is implicit)" do
      expect(Games::Filter.new(tokens: nil).dropped_tokens).to eq([])
    end

    it "is empty when every token is canonical" do
      expect(Games::Filter.new(tokens: %w[ps owned]).dropped_tokens).to eq([])
    end
  end

  describe "#contradiction? — always false in v2/v3" do
    it "returns false even for legacy contradiction-shaped inputs" do
      expect(Games::Filter.new(tokens: %w[owned not_owned]).contradiction?).to be(false)
    end
  end

  describe "#active_tokens alias" do
    it "is an alias of checked_tokens" do
      filter = Games::Filter.new(tokens: %w[ps owned])
      expect(filter.active_tokens).to eq(filter.checked_tokens)
    end
  end

  describe "defensive surface" do
    it "100-token bogus CSV falls back to empty checked set + Game.none" do
      tokens = Array.new(100) { |i| "bogus-#{i}" }
      filter = Games::Filter.new(scope: Game.all, tokens: tokens)
      expect(filter.checked_tokens).to eq([])
      expect(filter.results.to_a).to eq([])
    end

    it "SQL-injection-shaped token is dropped" do
      payload = "ps'; DROP TABLE games; --"
      filter = Games::Filter.new(scope: Game.all, tokens: [ payload ])
      expect(filter.dropped_tokens).to include(payload.downcase)
      expect(filter.checked_tokens).to eq([])
      expect(Game.table_exists?).to be(true)
    end
  end
end
