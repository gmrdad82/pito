# frozen_string_literal: true

require "rails_helper"

# Contract spec for the IGDB → pito release-date adapter.
#
# IGDB's `release_dates[]` rows carry a `category` enum (0..7) plus
# `y`, `m`, `d`, `date`, `human` fields. The adapter:
#
#   1. Picks the canonical row — the one whose `date` equals
#      `first_release_date`, falling back to the most-precise category
#      when `first_release_date` is null.
#   2. Translates IGDB's `category` into the pito component shape
#      (see `docs/architecture.md` § "Game release-date representation").
#   3. Feeds the result to `Pito::Game::ReleaseDateMapper` so the
#      output is the canonical 5-column attribute hash.
#
# IGDB `category` table:
#   0 day | 1 month | 2 year | 3..6 Q1..Q4 | 7 TBD
RSpec.describe Game::Igdb::GameMapper, ".map_game release-date handling" do
  def igdb_payload(first_release_date:, release_dates:)
    {
      "id"                  => 12345,
      "name"                => "Test Game",
      "first_release_date"  => first_release_date,
      "release_dates"       => release_dates
    }
  end

  def release_dates_row(category:, y: nil, m: nil, d: nil, date: nil)
    { "category" => category, "y" => y, "m" => m, "d" => d, "date" => date }
  end

  def unix(date)
    Time.utc(date.year, date.month, date.day).to_i
  end

  context "day precision (category 0)" do
    it "maps to year + month + day" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 10, 15)),
        release_dates: [
          release_dates_row(category: 0, y: 2026, m: 10, d: 15, date: unix(Date.new(2026, 10, 15)))
        ]
      )

      attrs = described_class.map_game(payload)

      expect(attrs[:release_year]).to eq(2026)
      expect(attrs[:release_month]).to eq(10)
      expect(attrs[:release_day]).to eq(15)
      expect(attrs[:release_quarter]).to be_nil
      expect(attrs[:release_date]).to eq(Date.new(2026, 10, 15))
    end
  end

  context "month precision (category 1)" do
    it "maps to year + month, day nil" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 10, 1)),
        release_dates: [
          release_dates_row(category: 1, y: 2026, m: 10, date: unix(Date.new(2026, 10, 1)))
        ]
      )

      attrs = described_class.map_game(payload)

      expect(attrs[:release_year]).to eq(2026)
      expect(attrs[:release_month]).to eq(10)
      expect(attrs[:release_day]).to be_nil
      expect(attrs[:release_date]).to eq(Date.new(2026, 10, 1))
    end
  end

  context "year precision (category 2)" do
    it "maps to year only" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 1, 1)),
        release_dates: [
          release_dates_row(category: 2, y: 2026, date: unix(Date.new(2026, 1, 1)))
        ]
      )

      attrs = described_class.map_game(payload)

      expect(attrs[:release_year]).to eq(2026)
      expect(attrs[:release_month]).to be_nil
      expect(attrs[:release_day]).to be_nil
      expect(attrs[:release_quarter]).to be_nil
      expect(attrs[:release_date]).to eq(Date.new(2026, 1, 1))
    end
  end

  context "quarter precision (categories 3..6)" do
    it "maps Q1 (category 3)" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 1, 1)),
        release_dates: [
          release_dates_row(category: 3, y: 2026, date: unix(Date.new(2026, 1, 1)))
        ]
      )

      attrs = described_class.map_game(payload)
      expect(attrs[:release_quarter]).to eq(1)
      expect(attrs[:release_month]).to be_nil
      expect(attrs[:release_date]).to eq(Date.new(2026, 1, 1))
    end

    it "maps Q3 (category 5)" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 7, 1)),
        release_dates: [
          release_dates_row(category: 5, y: 2026, date: unix(Date.new(2026, 7, 1)))
        ]
      )

      attrs = described_class.map_game(payload)
      expect(attrs[:release_quarter]).to eq(3)
      expect(attrs[:release_month]).to be_nil
      expect(attrs[:release_date]).to eq(Date.new(2026, 7, 1))
    end

    it "maps Q4 (category 6)" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 10, 1)),
        release_dates: [
          release_dates_row(category: 6, y: 2026, date: unix(Date.new(2026, 10, 1)))
        ]
      )

      attrs = described_class.map_game(payload)
      expect(attrs[:release_quarter]).to eq(4)
    end
  end

  context "TBD (category 7)" do
    it "maps to all-nil components when first_release_date is also nil" do
      payload = igdb_payload(
        first_release_date: nil,
        release_dates: [
          release_dates_row(category: 7, y: nil, date: nil)
        ]
      )

      attrs = described_class.map_game(payload)

      expect(attrs[:release_year]).to    be_nil
      expect(attrs[:release_quarter]).to be_nil
      expect(attrs[:release_month]).to   be_nil
      expect(attrs[:release_day]).to     be_nil
      expect(attrs[:release_date]).to    be_nil
    end
  end

  context "multi-row release_dates (canonical-row pick)" do
    it "picks the row whose date matches first_release_date" do
      target = unix(Date.new(2026, 10, 15))

      payload = igdb_payload(
        first_release_date: target,
        release_dates: [
          # Decoy row: Q3 placeholder before the canonical day-precision row
          release_dates_row(category: 5, y: 2026, date: unix(Date.new(2026, 7, 1))),
          # Canonical row
          release_dates_row(category: 0, y: 2026, m: 10, d: 15, date: target),
          # Decoy row: a later regional release
          release_dates_row(category: 0, y: 2027, m: 1, d: 1, date: unix(Date.new(2027, 1, 1)))
        ]
      )

      attrs = described_class.map_game(payload)

      expect(attrs[:release_date]).to eq(Date.new(2026, 10, 15))
      expect(attrs[:release_day]).to  eq(15)
    end
  end

  context "first_release_date null with a coarse category present" do
    it "falls back to the most-precise non-TBD row" do
      payload = igdb_payload(
        first_release_date: nil,
        release_dates: [
          release_dates_row(category: 7, date: nil),
          release_dates_row(category: 2, y: 2026, date: unix(Date.new(2026, 1, 1))),
          release_dates_row(category: 5, y: 2026, date: unix(Date.new(2026, 7, 1)))
        ]
      )

      attrs = described_class.map_game(payload)

      # Q3 (category 5) is more precise than year-only (category 2),
      # so the adapter picks the quarter row.
      expect(attrs[:release_quarter]).to eq(3)
      expect(attrs[:release_year]).to eq(2026)
      expect(attrs[:release_date]).to eq(Date.new(2026, 7, 1))
    end
  end

  context "no release_dates association at all" do
    it "falls back to first_release_date as day precision when present" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2024, 5, 1)),
        release_dates: nil
      )

      attrs = described_class.map_game(payload)
      expect(attrs[:release_date]).to eq(Date.new(2024, 5, 1))
    end

    it "yields all-nil components when both are missing" do
      payload = igdb_payload(first_release_date: nil, release_dates: nil)

      attrs = described_class.map_game(payload)
      expect(attrs[:release_year]).to be_nil
      expect(attrs[:release_date]).to be_nil
    end
  end

  context "columns intentionally NOT written by the adapter" do
    it "does not write a release_precision attribute (column is being dropped)" do
      payload = igdb_payload(
        first_release_date: unix(Date.new(2026, 10, 15)),
        release_dates: [
          release_dates_row(category: 0, y: 2026, m: 10, d: 15, date: unix(Date.new(2026, 10, 15)))
        ]
      )

      attrs = described_class.map_game(payload)
      expect(attrs).not_to have_key(:release_precision)
    end
  end
end
