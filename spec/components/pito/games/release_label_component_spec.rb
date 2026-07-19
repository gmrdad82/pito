# frozen_string_literal: true

require "rails_helper"

# Contract spec for the user-facing release-date label.
#
# The presenter renders one of six branches keyed off component
# nullability — see `docs/architecture.md` § "Game release-date
# representation". Implementation can be a
# `Pito::Games::ReleaseLabelComponent` or a plain `Game#release_label`
# helper; both expose the same string contract.
#
# i18n note: copy lives in `config/locales/pito/game/en.yml`. This spec
# asserts the visible English output as literal strings — readable and
# also a regression signal if someone edits the locale file by mistake.
# A separate spec (not here) would cover locale switching if pito ever
# adds non-English locales.
RSpec.describe "Pito::Games release label" do
  include ActiveSupport::Testing::TimeHelpers

  let(:render) do
    ->(game) {
      if defined?(Pito::Games::ReleaseLabelComponent)
        Pito::Games::ReleaseLabelComponent.new(game: game).call
      else
        game.release_label
      end
    }
  end

  # Day precision renders through the house date (Pito::Formatter::HouseDate)
  # — current year drops the year, any other year carries the '%y suffix.
  it "renders the house date for day precision — current year drops the year" do
    travel_to(Time.zone.local(2026, 7, 19)) do
      game = build(:game,
                   release_year: 2026, release_month: 10, release_day: 15,
                   release_date: Date.new(2026, 10, 15))

      expect(render.call(game)).to eq("15 Oct")
    end
  end

  it "renders the house date for day precision — another year carries the '%y suffix" do
    travel_to(Time.zone.local(2026, 7, 19)) do
      game = build(:game,
                   release_year: 2025, release_month: 10, release_day: 15,
                   release_date: Date.new(2025, 10, 15))

      expect(render.call(game)).to eq("15 Oct '25")
    end
  end

  it "renders 'Month YYYY' for month precision" do
    game = build(:game,
                 release_year: 2026, release_month: 10,
                 release_date: Date.new(2026, 10, 1))

    expect(render.call(game)).to eq("October 2026")
  end

  it "renders 'Q<n> YYYY' for quarter precision" do
    game = build(:game,
                 release_year: 2026, release_quarter: 3,
                 release_date: Date.new(2026, 7, 1))

    expect(render.call(game)).to eq("Q3 2026")
  end

  it "renders just the year for year-only precision" do
    game = build(:game,
                 release_year: 2026,
                 release_date: Date.new(2026, 1, 1))

    expect(render.call(game)).to eq("2026")
  end

  it "renders 'TBA' when no year is known and the row has been synced" do
    game = build(:game, release_year: nil, release_date: nil, igdb_synced_at: Time.current)

    expect(render.call(game)).to eq("TBA")
  end

  it "renders 'Month D' for manual month-day entries with no year" do
    game = build(:game,
                 release_year: nil, release_month: 12, release_day: 25,
                 release_date: nil)

    expect(render.call(game)).to eq("December 25")
  end
end
