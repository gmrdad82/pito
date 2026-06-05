# frozen_string_literal: true

require "rails_helper"

# Contract spec for `Pito::Game::ReleaseDateMapper` — the source-agnostic
# entry point that translates a normalized component hash into the
# 5-column attribute hash stored on `Game`.
#
# Documented in `docs/architecture.md` § "Game release-date representation".
#
# `ReleaseDateMapper.call` does NOT speak IGDB / Steam / Epic — adapters
# (e.g. `Game::Igdb::GameMapper`) translate their source's encoding into
# the input shape this mapper accepts.
#
# Input shape (every key optional):
#   { year: Integer, quarter: 1..4, month: 1..12, day: 1..31 }
#
# Output shape (always all 5 keys; nils explicit):
#   {
#     release_year: Integer | nil,
#     release_quarter: Integer | nil,
#     release_month: Integer | nil,
#     release_day: Integer | nil,
#     release_date: Date | nil,  # derived lower-bound; never the source of truth
#   }
RSpec.describe Pito::Game::ReleaseDateMapper do
  describe ".call" do
    context "when given a full date (day precision)" do
      it "returns the date as the lower bound" do
        result = described_class.call(year: 2026, month: 10, day: 15)

        expect(result).to eq(
          release_year:    2026,
          release_quarter: nil,
          release_month:   10,
          release_day:     15,
          release_date:    Date.new(2026, 10, 15)
        )
      end
    end

    context "when given month precision" do
      it "derives release_date as the first of the month" do
        result = described_class.call(year: 2026, month: 10)

        expect(result).to eq(
          release_year:    2026,
          release_quarter: nil,
          release_month:   10,
          release_day:     nil,
          release_date:    Date.new(2026, 10, 1)
        )
      end
    end

    context "when given quarter precision" do
      it "derives release_date as the first day of the quarter (Q1)" do
        result = described_class.call(year: 2026, quarter: 1)
        expect(result[:release_date]).to eq(Date.new(2026, 1, 1))
        expect(result[:release_quarter]).to eq(1)
        expect(result[:release_month]).to be_nil
      end

      it "derives release_date as the first day of Q2" do
        result = described_class.call(year: 2026, quarter: 2)
        expect(result[:release_date]).to eq(Date.new(2026, 4, 1))
      end

      it "derives release_date as the first day of Q3" do
        result = described_class.call(year: 2026, quarter: 3)
        expect(result[:release_date]).to eq(Date.new(2026, 7, 1))
      end

      it "derives release_date as the first day of Q4" do
        result = described_class.call(year: 2026, quarter: 4)
        expect(result[:release_date]).to eq(Date.new(2026, 10, 1))
      end
    end

    context "when given year precision only" do
      it "derives release_date as January 1 of that year" do
        result = described_class.call(year: 2026)

        expect(result).to eq(
          release_year:    2026,
          release_quarter: nil,
          release_month:   nil,
          release_day:     nil,
          release_date:    Date.new(2026, 1, 1)
        )
      end
    end

    context "when given an empty hash (TBA)" do
      it "returns all nils" do
        result = described_class.call({})

        expect(result).to eq(
          release_year:    nil,
          release_quarter: nil,
          release_month:   nil,
          release_day:     nil,
          release_date:    nil
        )
      end
    end

    context "when given nil" do
      it "returns all nils (treats nil as TBA)" do
        result = described_class.call(nil)

        expect(result).to eq(
          release_year:    nil,
          release_quarter: nil,
          release_month:   nil,
          release_day:     nil,
          release_date:    nil
        )
      end
    end

    context "when given month-day with no year (manual 'Christmas, year unknown')" do
      it "preserves month and day; release_date stays nil" do
        result = described_class.call(month: 12, day: 25)

        expect(result).to eq(
          release_year:    nil,
          release_quarter: nil,
          release_month:   12,
          release_day:     25,
          release_date:    nil
        )
      end
    end

    context "when given inconsistent components" do
      it "raises Pito::Error::ReleaseDateInconsistent when both quarter and month are present" do
        expect {
          described_class.call(year: 2026, quarter: 3, month: 7)
        }.to raise_error(Pito::Error::ReleaseDateInconsistent, /quarter and month are mutually exclusive/i)
      end

      it "raises Pito::Error::ReleaseDateInconsistent when day is present without month" do
        expect {
          described_class.call(year: 2026, day: 15)
        }.to raise_error(Pito::Error::ReleaseDateInconsistent, /day requires month/i)
      end

      it "raises when quarter is out of range" do
        expect {
          described_class.call(year: 2026, quarter: 5)
        }.to raise_error(Pito::Error::ReleaseDateInconsistent, /quarter out of range/i)
      end

      it "raises when month is out of range" do
        expect {
          described_class.call(year: 2026, month: 13)
        }.to raise_error(Pito::Error::ReleaseDateInconsistent, /month out of range/i)
      end

      it "raises when day is out of range for the given month" do
        expect {
          described_class.call(year: 2026, month: 2, day: 31)
        }.to raise_error(Pito::Error::ReleaseDateInconsistent, /invalid date/i)
      end
    end

    context "when keys are passed as strings (defensive)" do
      it "accepts string-keyed input" do
        result = described_class.call("year" => 2026, "month" => 10, "day" => 15)
        expect(result[:release_date]).to eq(Date.new(2026, 10, 15))
      end
    end
  end
end
