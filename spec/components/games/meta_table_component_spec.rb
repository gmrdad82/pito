require "rails_helper"

# Beta-3 Lane B (B3) — Games::MetaTableComponent.
#
# Pins down the meta-table business rule (Phase 14 §1 + 2026-05-11 Fix 3
# + 2026-05-18 sync row) in isolation from /games/:id:
#   - Row order: date, dev, pub, sync.
#   - Date / dev / pub rows omitted when the underlying value is blank.
#   - Sync row ALWAYS rendered; `---` while `resyncing?`, otherwise
#     `compact_time_ago(igdb_synced_at)` (which returns "never" for nil).
#   - Date value formatted as `%m-%d-%Y`.
RSpec.describe Games::MetaTableComponent, type: :component do
  # Stubs developers/publishers as plain object arrays so the component's
  # `.map(&:name)` call works without touching ActiveRecord. Uses a
  # local Struct (NOT named `Company`, which collides with the real AR
  # model) so factory-instantiation of company rows is unnecessary.
  StubCompany = Struct.new(:name) unless defined?(StubCompany)

  def stub_companies(game, developers: [], publishers: [])
    allow(game).to receive(:developers).and_return(developers.map { |n| StubCompany.new(n) })
    allow(game).to receive(:publishers).and_return(publishers.map { |n| StubCompany.new(n) })
  end

  describe "happy: all four fields present" do
    let(:game) do
      build_stubbed(:game,
        release_date: Date.new(2017, 3, 3),
        igdb_synced_at: 5.minutes.ago,
        resyncing: false)
    end

    before do
      stub_companies(game, developers: [ "Nintendo EPD" ], publishers: [ "Nintendo" ])
    end

    it "renders 4 rows in fixed order: date, dev, pub, sync" do
      render_inline(described_class.new(game: game))
      labels = page.all("td.kv-table__label").map { |n| n.text.strip }
      expect(labels).to eq(%w[date dev pub sync])
    end

    it "formats the date as %m-%d-%Y" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("td.kv-table__value", text: "03-03-2017")
    end

    it "renders the dev value as the comma-joined developer name list" do
      stub_companies(game, developers: [ "Nintendo EPD", "Monolith Soft" ], publishers: [ "Nintendo" ])
      render_inline(described_class.new(game: game))
      expect(page).to have_css("td.kv-table__value", text: "Nintendo EPD, Monolith Soft")
    end

    it "renders the pub value as the comma-joined publisher name list" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("td.kv-table__value", text: "Nintendo")
    end
  end

  describe "edge: release_date absent" do
    let(:game) do
      build_stubbed(:game,
        release_date: nil,
        igdb_synced_at: Time.current,
        resyncing: false)
    end

    before { stub_companies(game, developers: [ "Acme" ], publishers: [ "Acme Pub" ]) }

    it "omits the date row entirely" do
      render_inline(described_class.new(game: game))
      labels = page.all("td.kv-table__label").map { |n| n.text.strip }
      expect(labels).to eq(%w[dev pub sync])
    end
  end

  describe "edge: no developers" do
    let(:game) do
      build_stubbed(:game,
        release_date: Date.new(2020, 1, 1),
        igdb_synced_at: Time.current,
        resyncing: false)
    end

    before { stub_companies(game, developers: [], publishers: [ "Acme Pub" ]) }

    it "omits the dev row entirely" do
      render_inline(described_class.new(game: game))
      labels = page.all("td.kv-table__label").map { |n| n.text.strip }
      expect(labels).to eq(%w[date pub sync])
    end
  end

  describe "edge: no publishers" do
    let(:game) do
      build_stubbed(:game,
        release_date: Date.new(2020, 1, 1),
        igdb_synced_at: Time.current,
        resyncing: false)
    end

    before { stub_companies(game, developers: [ "Acme" ], publishers: []) }

    it "omits the pub row entirely" do
      render_inline(described_class.new(game: game))
      labels = page.all("td.kv-table__label").map { |n| n.text.strip }
      expect(labels).to eq(%w[date dev sync])
    end
  end

  describe "sync row — resyncing? true" do
    let(:game) do
      build_stubbed(:game,
        release_date: nil,
        igdb_synced_at: 5.minutes.ago,
        resyncing: true)
    end

    before { stub_companies(game) }

    it "renders the sync cell as `---` (NOT compact_time_ago)" do
      render_inline(described_class.new(game: game))
      sync_value = page.all("tr").last.find("td.kv-table__value").text.strip
      expect(sync_value).to eq("---")
    end

    # 2026-05-19 (Bug A3 fix) — sync row carries a stable id so Turbo
    # morph (page-level auto-refresh polling) identifies the same node
    # across renders and reliably swaps the value cell text. Without
    # this anchor, morph was free to reuse `<td>` shells and leave the
    # stale time-ago string in place.
    it "renders the sync row with a stable DOM id" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("tr#game_meta_sync_row_#{game.id}")
    end

    it "renders the sync row with the `kv-table__row--syncing` modifier class" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("tr#game_meta_sync_row_#{game.id}.kv-table__row--syncing")
    end

    it "marks the sync row with `data-resyncing=yes` (yes/no boundary contract)" do
      render_inline(described_class.new(game: game))
      row = page.find("tr#game_meta_sync_row_#{game.id}")
      expect(row["data-resyncing"]).to eq("yes")
    end
  end

  describe "sync row — resyncing? false + igdb_synced_at present" do
    let(:synced_at) { 2.minutes.ago }
    let(:game) do
      build_stubbed(:game,
        release_date: nil,
        igdb_synced_at: synced_at,
        resyncing: false)
    end

    before { stub_companies(game) }

    it "renders the sync cell via compact_time_ago(igdb_synced_at)" do
      # Compact format is "~Xm ago" for the 60s..3600s bucket — the
      # helper itself is covered by its own spec; here we assert the
      # component delegates to it (matches the same string the helper
      # would produce for the same input).
      expected = ApplicationController.helpers.compact_time_ago(synced_at)
      render_inline(described_class.new(game: game))
      sync_value = page.all("tr").last.find("td.kv-table__value").text.strip
      expect(sync_value).to eq(expected)
      expect(sync_value).to match(/\A~\d+m ago\z/)
    end

    # 2026-05-19 (Bug A3 fix) — when NOT resyncing, the sync row still
    # carries the stable id (so Turbo morph keeps the anchor stable
    # across the resync → not-resyncing transition) but neither the
    # `--syncing` modifier class nor `data-resyncing=yes`.
    it "renders the sync row with the stable DOM id even when not resyncing" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("tr#game_meta_sync_row_#{game.id}")
    end

    it "does NOT apply the `kv-table__row--syncing` modifier class" do
      render_inline(described_class.new(game: game))
      expect(page).not_to have_css("tr.kv-table__row--syncing")
    end

    it "marks the sync row with `data-resyncing=no`" do
      render_inline(described_class.new(game: game))
      row = page.find("tr#game_meta_sync_row_#{game.id}")
      expect(row["data-resyncing"]).to eq("no")
    end
  end

  # 2026-05-19 (Wave B) — when `resyncing?` is true, the date / dev /
  # pub value cells render as `sync-indicator` dot-loaders at phase
  # offsets 1 / 2 / 3 respectively (genre line is 0, summary is back
  # to 0). The rows are force-rendered even when the underlying value
  # is blank so the loaders have a home; the static `---` value of
  # the sync row stays in place (the row-level dim layer carries the
  # muted-stale treatment).
  describe "Wave B — dot-loader cells on date / dev / pub during resync" do
    let(:game) do
      build_stubbed(:game,
        release_date: Date.new(2017, 3, 3),
        igdb_synced_at: 5.minutes.ago,
        resyncing: true)
    end

    before do
      stub_companies(game, developers: [ "Nintendo EPD" ], publishers: [ "Nintendo" ])
    end

    {
      "date" => 1,
      "dev"  => 2,
      "pub"  => 3
    }.each do |label, offset|
      it "renders the `#{label}` value cell as a sync-indicator with phase offset #{offset}" do
        render_inline(described_class.new(game: game))
        row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == label }
        cell = row.find("td.kv-table__value")
        expect(cell["data-controller"]).to eq("sync-indicator")
        expect(cell["data-sync-indicator-phase-offset-value"]).to eq(offset.to_s)
      end

      it "seeds the `#{label}` cell text with the offset-#{offset} frame" do
        render_inline(described_class.new(game: game))
        row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == label }
        cell = row.find("td.kv-table__value")
        expected_seed = described_class::SYNC_INDICATOR_FRAMES[offset]
        expect(cell.text.strip).to eq(expected_seed)
      end

      it "carries the canonical 4-frame cycle on the `#{label}` cell" do
        render_inline(described_class.new(game: game))
        row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == label }
        cell = row.find("td.kv-table__value")
        frames = JSON.parse(cell["data-sync-indicator-frames-value"])
        expect(frames).to eq([ "=---", "-=--", "--=-", "---=" ])
      end

      it "marks the `#{label}` cell with `data-resyncing=yes`" do
        render_inline(described_class.new(game: game))
        row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == label }
        cell = row.find("td.kv-table__value")
        expect(cell["data-resyncing"]).to eq("yes")
      end
    end

    it "keeps the sync row's `---` value cell WITHOUT a sync-indicator controller" do
      render_inline(described_class.new(game: game))
      sync_cell = page.find("tr#game_meta_sync_row_#{game.id} td.kv-table__value")
      expect(sync_cell["data-controller"]).to be_nil
      expect(sync_cell.text.strip).to eq("---")
    end
  end

  describe "Wave B — force-render date/dev/pub rows during resync even when value blank" do
    let(:game) do
      build_stubbed(:game,
        release_date: nil,
        igdb_synced_at: nil,
        resyncing: true)
    end

    before { stub_companies(game, developers: [], publishers: []) }

    it "renders date / dev / pub / sync rows (so loaders have a home)" do
      render_inline(described_class.new(game: game))
      labels = page.all("td.kv-table__label").map { |n| n.text.strip }
      expect(labels).to eq(%w[date dev pub sync])
    end

    it "renders the date cell as a sync-indicator even with no release_date" do
      render_inline(described_class.new(game: game))
      row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == "date" }
      cell = row.find("td.kv-table__value")
      expect(cell["data-controller"]).to eq("sync-indicator")
    end

    it "renders the dev cell as a sync-indicator even with no developers" do
      render_inline(described_class.new(game: game))
      row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == "dev" }
      cell = row.find("td.kv-table__value")
      expect(cell["data-controller"]).to eq("sync-indicator")
    end

    it "renders the pub cell as a sync-indicator even with no publishers" do
      render_inline(described_class.new(game: game))
      row = page.all("tr").find { |tr| tr.find("td.kv-table__label").text.strip == "pub" }
      cell = row.find("td.kv-table__value")
      expect(cell["data-controller"]).to eq("sync-indicator")
    end
  end

  describe "Wave B — NOT resyncing: no sync-indicator controllers anywhere" do
    let(:game) do
      build_stubbed(:game,
        release_date: Date.new(2017, 3, 3),
        igdb_synced_at: 5.minutes.ago,
        resyncing: false)
    end

    before do
      stub_companies(game, developers: [ "Nintendo EPD" ], publishers: [ "Nintendo" ])
    end

    it "does not attach the sync-indicator controller to any cell" do
      render_inline(described_class.new(game: game))
      expect(page).to have_no_css("[data-controller='sync-indicator']")
    end
  end

  describe "phase_offset_for" do
    let(:game) { build_stubbed(:game, resyncing: false) }

    it "returns 1 for `date`" do
      expect(described_class.new(game: game).phase_offset_for("date")).to eq(1)
    end

    it "returns 2 for `dev`" do
      expect(described_class.new(game: game).phase_offset_for("dev")).to eq(2)
    end

    it "returns 3 for `pub`" do
      expect(described_class.new(game: game).phase_offset_for("pub")).to eq(3)
    end

    it "returns 0 for unknown keys (defensive default)" do
      expect(described_class.new(game: game).phase_offset_for("anything-else")).to eq(0)
    end
  end
end
