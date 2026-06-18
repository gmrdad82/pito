# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReleaseCountdownJob, type: :job do
  def run!
    described_class.new.perform
  end

  # Builds a game whose derived release_date lands `days` from today by setting
  # its year/month/day components (release_date is recomputed before_save).
  def game_releasing_in(days, **attrs)
    target = Date.current + days
    create(:game,
           release_year:  target.year,
           release_month: target.month,
           release_day:   target.day,
           **attrs)
  end

  describe "#perform" do
    it "creates exactly one countdown notification for a game releasing within 30 days" do
      game_releasing_in(10)
      expect { run! }.to change(Notification, :count).by(1)
    end

    it "creates no notification for a date-less (TBA, nil release_date) game" do
      tba = create(:game, :tba)
      expect(tba.release_date).to be_nil

      expect { run! }.not_to change(Notification, :count)
    end

    it "creates no notification for a game releasing beyond the 30-day window" do
      game_releasing_in(45)
      expect { run! }.not_to change(Notification, :count)
    end

    it "creates no notification for an already-released (past) game" do
      create(:game, release_year: 2020, release_month: 3, release_day: 15)
      expect { run! }.not_to change(Notification, :count)
    end

    it "embeds the days-remaining count and the title in the message" do
      game = game_releasing_in(7, title: "Hollow Knight: Silksong")
      run!
      msg = Notification.last.message
      expect(msg).to include("7")
      expect(msg).to include("Hollow Knight: Silksong")
    end

    it "does not create a duplicate when run twice on the same day" do
      game_releasing_in(10)
      run!
      expect { run! }.not_to change(Notification, :count)
    end

    it "still reminds a different game on a same-day re-run" do
      game_releasing_in(10, title: "Game One")
      run!
      game_releasing_in(12, title: "Game Two")
      expect { run! }.to change(Notification, :count).by(1)
    end
  end
end
