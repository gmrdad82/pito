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
  end
end
