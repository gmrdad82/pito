require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. The decorator owns the
# JSON wire shape for games (summary + detail). Boundary booleans
# serialize as "yes"/"no" strings (CLAUDE.md hard rule); timestamps as
# ISO-8601.
RSpec.describe GameDecorator do
  let(:game) do
    create(
      :game,
      :synced,
      title: "The Witness",
      release_year: 2016,
      igdb_rating: 87.4,
      played_at: Date.new(2024, 1, 12),
      resyncing: false
    )
  end
  let(:decorator) { described_class.new(game) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "carries the row-level keys" do
      expect(json.keys).to match_array(
        %i[id slug title release_year igdb_rating platform_owned_ids
           played_at cover_image_id resyncing igdb_synced_at created_at]
      )
    end

    it "serializes resyncing as the yes/no string" do
      expect(json[:resyncing]).to eq("no")

      game.update_column(:resyncing, true)
      expect(described_class.new(game.reload).as_summary_json[:resyncing]).to eq("yes")
    end

    it "serializes igdb_rating as a Float (Rust f64)" do
      expect(json[:igdb_rating]).to be_a(Float)
      expect(json[:igdb_rating]).to be_within(0.01).of(87.4)
    end

    it "serializes timestamps as ISO-8601" do
      expect(json[:igdb_synced_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(json[:created_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "serializes played_at (a Date) as ISO-8601" do
      expect(json[:played_at]).to eq("2024-01-12")
    end

    it "exposes the IGDB slug" do
      expect(json[:slug]).to eq(game.igdb_slug)
    end

    it "emits empty / null (not 0) when associations are absent" do
      bare = create(:game, title: "Bare")
      summary = described_class.new(bare).as_summary_json
      # Phase 27 §1a — multi-valued ownership: an empty array stands
      # for "owned on no platform".
      expect(summary[:platform_owned_ids]).to eq([])
      expect(summary[:cover_image_id]).to be_nil
      expect(summary[:igdb_synced_at]).to be_nil
    end
  end

  describe "#as_detail_json" do
    let(:json) { decorator.as_detail_json }

    it "includes every summary key" do
      expect(json).to include(*decorator.as_summary_json.keys)
    end

    it "adds the detail-only fields" do
      # Phase 27 v2 spec 01 — wire shape collapses multi-genre `:genres`
      # list to a singular `:genre` string. Key set updated.
      # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `external_gog_id`
      # / `external_epic_id` retired; only `external_steam_app_id` survives.
      expect(json).to include(
        :igdb_id, :summary, :release_date, :igdb_rating_count,
        :aggregated_rating, :total_rating, :total_rating_count,
        :ttb_main_seconds, :ttb_extras_seconds, :ttb_completionist_seconds,
        :external_steam_app_id,
        :notes, :hours_of_footage_manual, :hours_of_footage_cached,
        :manual_date_override, :last_sync_error, :genre,
        :platforms_owning, :updated_at
      )
    end

    it "does NOT carry the retired external_gog_id / external_epic_id keys (2026-05-17 PC store collapse)" do
      expect(json).not_to have_key(:external_gog_id)
      expect(json).not_to have_key(:external_epic_id)
    end

    it "does NOT carry the legacy multi-genre :genres list (Phase 27 v2 spec 01)" do
      expect(json).not_to have_key(:genres)
    end

    it "serializes manual_date_override as yes/no" do
      expect(json[:manual_date_override]).to eq("no")
    end

    it "renders :genre as the primary genre's name when set" do
      genre = create(:genre, name: "Puzzle")
      game.genres << genre
      detail = described_class.new(game.reload).as_detail_json
      expect(detail[:genre]).to eq("Puzzle")
    end

    it "renders :genre as nil when the game has no primary genre" do
      bare = create(:game, title: "Bare")
      detail = described_class.new(bare).as_detail_json
      expect(detail[:genre]).to be_nil
    end

    it "renders :genre using the picker's case-insensitive alphabetical winner" do
      action = create(:genre, name: "Action",    igdb_id: 7_001)
      zelda  = create(:genre, name: "adventure", igdb_id: 7_002)
      multi  = create(:game, title: "Multi-genre detail")
      multi.genres << [ action, zelda ]
      detail = described_class.new(multi.reload).as_detail_json
      # "action" < "adventure" by LOWER(name); both are < anything
      # starting with "z" by lowercase ordering.
      expect(detail[:genre]).to eq("Action")
    end

    it "renders platforms_owning when ownership rows exist" do
      platform = create(:platform, name: "Steam", slug: "steam-decorator-spec")
      game.game_platform_ownerships.create!(platform: platform)
      detail = described_class.new(game.reload).as_detail_json
      expect(detail[:platforms_owning]).to eq([ { id: platform.id, name: "Steam" } ])
    end

    it "renders platforms_owning as [] when no ownership rows" do
      expect(json[:platforms_owning]).to eq([])
    end

    it "renders multiple ownership entries alphabetically by platform name" do
      ps5   = create(:platform, name: "PS5",   slug: "ps5-decorator-spec")
      steam = create(:platform, name: "Steam", slug: "steam-decorator-multi")
      game.game_platform_ownerships.create!(platform: steam)
      game.game_platform_ownerships.create!(platform: ps5)
      detail = described_class.new(game.reload).as_detail_json
      expect(detail[:platforms_owning].map { |h| h[:name] }).to eq([ "PS5", "Steam" ])
    end

    it "coerces decimal ratings to Float" do
      expect(json[:total_rating]).to be_a(Float) if json[:total_rating]
      expect(json[:aggregated_rating]).to be_a(Float) if json[:aggregated_rating]
    end
  end
end
