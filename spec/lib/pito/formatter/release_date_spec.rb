# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::ReleaseDate do
  describe ".call" do
    # ── Full date (day precision) ────────────────────────────────────────────
    # release_date must be persisted so I18n.l can render it;
    # recompute_release_date runs in before_save, hence `create`.
    it "renders a full date as long format: 'June 09, 2026'" do
      game = create(:game, release_year: 2026, release_month: 6, release_day: 9)
      expect(described_class.call(game)).to eq("June 09, 2026")
    end

    # ── Month-year (month precision, no day) ─────────────────────────────────
    it "renders month + year as 'June 2026'" do
      game = build(:game, release_year: 2026, release_month: 6)
      expect(described_class.call(game)).to eq("June 2026")
    end

    # ── Quarter-year precision ────────────────────────────────────────────────
    it "renders quarter + year as 'Q2 2026'" do
      game = build(:game, release_year: 2026, release_quarter: 2)
      expect(described_class.call(game)).to eq("Q2 2026")
    end

    # ── Year-only precision ───────────────────────────────────────────────────
    it "renders year-only as '2026'" do
      game = build(:game, release_year: 2026)
      expect(described_class.call(game)).to eq("2026")
    end

    # ── TBA (year nil, no month/day) ─────────────────────────────────────────
    it "renders 'TBA' when release_year is nil and no month/day" do
      game = build(:game, release_year: nil, release_quarter: nil,
                          release_month: nil, release_day: nil)
      expect(described_class.call(game)).to eq("TBA")
    end

    # ── Month + day, unknown year ─────────────────────────────────────────────
    it "renders month + day without year when release_year is nil" do
      game = build(:game, release_year: nil, release_month: 12, release_day: 25)
      expect(described_class.call(game)).to eq("December 25")
    end
  end
end
