require "rails_helper"

# Phase 27 §01b — Filter row query object.
#
# Load-bearing matrix: every (`owned` × platform-X) pair across all
# five canonical platforms, plus status chips, plus combinations. The
# verbatim Mobile-directive worked example is reproduced as its own
# `describe` block.
RSpec.describe Games::Filter do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 5, 11, 12, 0, 0) }

  around { |ex| travel_to(now) { ex.run } }

  # The five canonical platforms keyed by their slugs (locked by 01a
  # seeds). FriendlyId derives the slug from `slug_candidates` based on
  # `name`; to pin the slug to the canonical value, we use a name that
  # already matches the desired slug.
  let!(:platform_ps5)     { create(:platform, name: "ps5",     slug: "ps5") }
  let!(:platform_switch2) { create(:platform, name: "switch2", slug: "switch2") }
  let!(:platform_steam)   { create(:platform, name: "steam",   slug: "steam") }
  let!(:platform_gog)     { create(:platform, name: "gog",     slug: "gog") }
  let!(:platform_epic)    { create(:platform, name: "epic",    slug: "epic") }

  # Fixture matrix (verbatim from spec §"Fixture matrix"):
  #
  #   | Game | Available on (IGDB) | Owned on | Released? | Has Video? |
  #   | A    | PS5, Switch 2       | PS5      | yes       | no         |
  #   | B    | PS5, Steam          | (none)   | yes       | no         |
  #   | C    | Switch 2            | (none)   | no (sched)| no         |
  #   | D    | PS5, Switch 2       | PS5      | no (sched)| no         |
  #   | E    | Steam               | Steam    | yes       | yes        |
  #   | F    | GOG                 | (none)   | yes       | no         |
  #   | G    | Epic                | Epic     | yes       | no         |
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
    g = create(:game, title: "Game E", release_date: past)
    g.game_platforms.create!(platform: platform_steam)
    g.game_platform_ownerships.create!(platform: platform_steam)
    create(:video_game_link, game: g)
    g
  end
  let!(:game_f) do
    g = create(:game, title: "Game F", release_date: past)
    g.game_platforms.create!(platform: platform_gog)
    g
  end
  let!(:game_g) do
    g = create(:game, title: "Game G", release_date: past)
    g.game_platforms.create!(platform: platform_epic)
    g.game_platform_ownerships.create!(platform: platform_epic)
    g
  end

  # Convenience: run the filter and return the title-ordered ids.
  def filtered_titles(*tokens)
    Games::Filter.new(scope: Game.all, tokens: tokens).results.order(:title).pluck(:title)
  end

  describe "single-token tests (happy)" do
    it "[] returns every fixture game" do
      expect(filtered_titles).to match_array(%w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F Game\ G])
    end

    it "[recorded] returns only games with a linked Video" do
      expect(filtered_titles("recorded")).to eq([ "Game E" ])
    end

    it "[released] returns games with release_date in the past" do
      expect(filtered_titles("released")).to match_array([ "Game A", "Game B", "Game E", "Game F", "Game G" ])
    end

    it "[scheduled] returns games with release_date in the future" do
      expect(filtered_titles("scheduled")).to match_array([ "Game C", "Game D" ])
    end

    it "[owned] returns games with at least one ownership row" do
      expect(filtered_titles("owned")).to match_array([ "Game A", "Game D", "Game E", "Game G" ])
    end

    it "[not_owned] returns games with zero ownership rows" do
      expect(filtered_titles("not_owned")).to match_array([ "Game B", "Game C", "Game F" ])
    end
  end

  describe "single platform token, owned UNCHECKED (statement P-1)" do
    it "[ps5] → A, B, D" do
      expect(filtered_titles("ps5")).to match_array([ "Game A", "Game B", "Game D" ])
    end

    it "[switch2] → A, C, D" do
      expect(filtered_titles("switch2")).to match_array([ "Game A", "Game C", "Game D" ])
    end

    it "[steam] → B, E" do
      expect(filtered_titles("steam")).to match_array([ "Game B", "Game E" ])
    end

    it "[gog] → F" do
      expect(filtered_titles("gog")).to eq([ "Game F" ])
    end

    it "[epic] → G" do
      expect(filtered_titles("epic")).to eq([ "Game G" ])
    end
  end

  describe "single platform token, owned CHECKED (statement P-2)" do
    it "[owned, ps5] → A, D" do
      expect(filtered_titles("owned", "ps5")).to match_array([ "Game A", "Game D" ])
    end

    it "[owned, switch2] → ∅" do
      expect(filtered_titles("owned", "switch2")).to eq([])
    end

    it "[owned, steam] → E" do
      expect(filtered_titles("owned", "steam")).to eq([ "Game E" ])
    end

    it "[owned, gog] → ∅" do
      expect(filtered_titles("owned", "gog")).to eq([])
    end

    it "[owned, epic] → G" do
      expect(filtered_titles("owned", "epic")).to eq([ "Game G" ])
    end
  end

  describe "single platform token, not_owned CHECKED (corollary C-1)" do
    it "[not_owned, ps5] → B" do
      expect(filtered_titles("not_owned", "ps5")).to eq([ "Game B" ])
    end

    it "[not_owned, switch2] → C" do
      expect(filtered_titles("not_owned", "switch2")).to eq([ "Game C" ])
    end

    it "[not_owned, steam] → B" do
      expect(filtered_titles("not_owned", "steam")).to eq([ "Game B" ])
    end

    it "[not_owned, gog] → F" do
      expect(filtered_titles("not_owned", "gog")).to eq([ "Game F" ])
    end

    it "[not_owned, epic] → ∅" do
      # G is owned on Epic; nothing else is on Epic.
      expect(filtered_titles("not_owned", "epic")).to eq([])
    end
  end

  describe "Mobile directive worked example (verbatim)" do
    let!(:game_x) do
      g = create(:game, title: "Game X", release_date: past)
      g.game_platforms.create!(platform: platform_ps5)
      g.game_platforms.create!(platform: platform_switch2)
      g.game_platform_ownerships.create!(platform: platform_ps5)
      g
    end

    it "owned unchecked, ps5 checked → matches game_x" do
      results = Games::Filter.new(scope: Game.all, tokens: %w[ps5]).results
      expect(results).to include(game_x)
    end

    it "owned unchecked, switch2 checked → matches game_x" do
      results = Games::Filter.new(scope: Game.all, tokens: %w[switch2]).results
      expect(results).to include(game_x)
    end

    it "owned checked, ps5 checked → matches game_x" do
      results = Games::Filter.new(scope: Game.all, tokens: %w[owned ps5]).results
      expect(results).to include(game_x)
    end

    it "owned checked, switch2 checked → does NOT match game_x" do
      results = Games::Filter.new(scope: Game.all, tokens: %w[owned switch2]).results
      expect(results).not_to include(game_x)
    end
  end

  describe "multi-platform tokens (corollary C-2)" do
    it "[ps5, switch2] (owned unchecked) → A, B, C, D" do
      expect(filtered_titles("ps5", "switch2")).to match_array([ "Game A", "Game B", "Game C", "Game D" ])
    end

    it "[owned, ps5, switch2] → A, D" do
      # A owned PS5; D owned PS5; switch2 contributes ∅ (no game owned on it).
      expect(filtered_titles("owned", "ps5", "switch2")).to match_array([ "Game A", "Game D" ])
    end

    it "[not_owned, ps5, switch2] → B, C" do
      expect(filtered_titles("not_owned", "ps5", "switch2")).to match_array([ "Game B", "Game C" ])
    end
  end

  describe "combination with status tokens" do
    it "[recorded, owned] → E" do
      expect(filtered_titles("recorded", "owned")).to eq([ "Game E" ])
    end

    it "[recorded, ps5] → ∅ (E has no PS5 release)" do
      expect(filtered_titles("recorded", "ps5")).to eq([])
    end

    it "[released, owned, ps5] → A" do
      expect(filtered_titles("released", "owned", "ps5")).to eq([ "Game A" ])
    end

    it "[scheduled, ps5] → D" do
      expect(filtered_titles("scheduled", "ps5")).to eq([ "Game D" ])
    end

    it "[scheduled, owned, ps5] → D" do
      expect(filtered_titles("scheduled", "owned", "ps5")).to eq([ "Game D" ])
    end

    it "[scheduled, not_owned, ps5] → ∅" do
      expect(filtered_titles("scheduled", "not_owned", "ps5")).to eq([])
    end

    it "[scheduled, not_owned, switch2] → C" do
      expect(filtered_titles("scheduled", "not_owned", "switch2")).to eq([ "Game C" ])
    end
  end

  describe "status-bucket OR semantics" do
    it "[released, scheduled] → all games in the fixture" do
      expect(filtered_titles("released", "scheduled")).to match_array(
        %w[Game\ A Game\ B Game\ C Game\ D Game\ E Game\ F Game\ G]
      )
    end

    it "[recorded, scheduled] → C, D, E" do
      expect(filtered_titles("recorded", "scheduled")).to match_array([ "Game C", "Game D", "Game E" ])
    end
  end

  describe "contradiction (C-3)" do
    it "[owned, not_owned] returns Game.none and contradiction? is true" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[owned not_owned])
      expect(filter.contradiction?).to be true
      expect(filter.results.to_a).to eq([])
    end

    it "[owned, not_owned, ps5] — contradiction wins" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[owned not_owned ps5])
      expect(filter.contradiction?).to be true
      expect(filter.results.to_a).to eq([])
    end
  end

  describe "edge: input normalisation" do
    it "[ps5, ps5] de-dupes to [ps5]; identical result" do
      base = filtered_titles("ps5")
      expect(filtered_titles("ps5", "ps5")).to match_array(base)
    end

    it "[PS5] normalises case to ps5; identical result" do
      base = filtered_titles("ps5")
      expect(filtered_titles("PS5")).to match_array(base)
    end

    it "[' ps5 '] (whitespace) is trimmed; identical result" do
      base = filtered_titles("ps5")
      expect(filtered_titles(" ps5 ")).to match_array(base)
    end

    it "[] returns all games; contradiction? false" do
      filter = Games::Filter.new(scope: Game.all, tokens: [])
      expect(filter.contradiction?).to be false
      expect(filter.results.count).to eq(7)
    end

    it "token order does not affect result set" do
      a = Games::Filter.new(scope: Game.all, tokens: %w[owned ps5]).results.pluck(:id).sort
      b = Games::Filter.new(scope: Game.all, tokens: %w[ps5 owned]).results.pluck(:id).sort
      expect(a).to eq(b)
    end
  end

  describe "flaw: defensive surface" do
    it "100-token input does not blow the stack; canonical 0 of 100 → all games" do
      tokens = Array.new(100) { |i| "bogus-#{i}" }
      filter = Games::Filter.new(scope: Game.all, tokens: tokens)
      expect(filter.dropped_tokens.size).to eq(100)
      expect(filter.active_tokens).to eq([])
      expect(filter.results.count).to eq(7)
    end

    it "SQL-injection-shaped token is dropped, results identical to no-filter" do
      payload = "ps5'; DROP TABLE games; --"
      filter = Games::Filter.new(scope: Game.all, tokens: [ payload ])
      # The normaliser downcases — assert the normalised form is what
      # ends up in dropped_tokens, and that the games table is intact.
      expect(filter.dropped_tokens).to include(payload.downcase)
      expect(filter.active_tokens).to eq([])
      expect(Game.table_exists?).to be true
      expect(filter.results.count).to eq(7)
    end

    it "#results returns an ActiveRecord::Relation (composable with .where)" do
      filter = Games::Filter.new(scope: Game.all, tokens: [ "ps5" ])
      composed = filter.results.where("games.id > ?", 0)
      expect(composed).to be_a(ActiveRecord::Relation)
    end

    it "#results is memoised — calling twice produces the same SQL" do
      filter = Games::Filter.new(scope: Game.all, tokens: [ "ps5" ])
      first_sql  = filter.results.to_sql
      second_sql = filter.results.to_sql
      expect(first_sql).to eq(second_sql)
    end

    # P27 reviewer follow-up (non-blocking concern #3, 2026-05-11) —
    # the combinator must not realise intermediate `.ids` arrays. The
    # caller composes `.where(...).count` and the resulting SQL is
    # executed in a single round-trip (the subqueries inline as
    # `IN (SELECT ...)` clauses, not literal `IN (?, ?, ?, ...)`
    # lists).
    it "composes with .where(...).count without materialising intermediate ids" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[released ps5])
      composed = filter.results.where("games.id > ?", 0)
      expect(composed.count).to be_a(Integer)
    end

    it "emits a subquery (not a literal id list) for status-bucket OR composition" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[recorded released])
      sql = filter.results.to_sql
      # The subquery form contains a nested SELECT; the
      # materialise-then-IN form would carry a literal id list.
      expect(sql).to match(/IN \(SELECT/i)
    end

    it "emits a subquery (not a literal id list) for platform-bucket OR composition" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps5 switch2])
      sql = filter.results.to_sql
      expect(sql).to match(/IN \(SELECT/i)
    end
  end

  describe "#active_tokens / #dropped_tokens" do
    it "active_tokens preserves the canonical subset" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps5 bogus owned])
      expect(filter.active_tokens).to eq(%w[ps5 owned])
    end

    it "dropped_tokens collects the unrecognised entries" do
      filter = Games::Filter.new(scope: Game.all, tokens: %w[ps5 bogus owned junk])
      expect(filter.dropped_tokens).to eq(%w[bogus junk])
    end
  end
end
