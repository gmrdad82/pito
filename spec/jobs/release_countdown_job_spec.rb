# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReleaseCountdownJob, type: :job do
  def run!
    described_class.new.perform
  end

  # Attaches a DAY-precision per-platform release landing `days` from today.
  def release_in(days, token: "ps", game: create(:game))
    target = Date.current + days
    create(:game_platform_release,
           game:          game,
           platform_token: token,
           release_year:  target.year,
           release_month: target.month,
           release_day:   target.day)
    game
  end

  describe "#perform" do
    it "creates one countdown for a day-precision release within 30 days" do
      release_in(10)
      expect { run! }.to change(Notification, :count).by(1)
    end

    it "creates no notification for a TBA game (no dated release)" do
      create(:game, :tba)
      expect { run! }.not_to change(Notification, :count)
    end

    it "creates no notification for a QUARTER-precision release (not a real day)" do
      g = create(:game)
      create(:game_platform_release, game: g, platform_token: "switch",
             release_year: Date.current.year, release_quarter: 3, release_month: nil, release_day: nil)
      expect { run! }.not_to change(Notification, :count)
    end

    it "creates no notification beyond the 30-day window" do
      release_in(45)
      expect { run! }.not_to change(Notification, :count)
    end

    it "creates no notification for a past release" do
      release_in(-5)
      expect { run! }.not_to change(Notification, :count)
    end

    it "names the platform(s), days-remaining, and title in the message" do
      g = create(:game, title: "Hollow Knight: Silksong")
      release_in(7, token: "ps", game: g)
      release_in(7, token: "steam", game: g)
      run!
      msg = Notification.last.message
      expect(msg).to include("7").and include("Hollow Knight: Silksong")
      expect(msg).to include("PlayStation + Steam")
    end

    it "fires SEPARATE notifications when platforms have different dates" do
      g = create(:game)
      release_in(5, token: "ps", game: g)
      release_in(12, token: "switch", game: g)
      expect { run! }.to change(Notification, :count).by(2)
    end

    it "does not duplicate on a same-day re-run" do
      release_in(10)
      run!
      expect { run! }.not_to change(Notification, :count)
    end

    it "still reminds a different game on a same-day re-run" do
      release_in(10, game: create(:game, title: "Game One"))
      run!
      release_in(12, game: create(:game, title: "Game Two"))
      expect { run! }.to change(Notification, :count).by(1)
    end

    it "includes 30 days out (inclusive) and today (0 days)" do
      release_in(30)
      release_in(0)
      expect { run! }.to change(Notification, :count).by(2)
    end

    it "excludes 31 days out (just past the window)" do
      release_in(31)
      expect { run! }.not_to change(Notification, :count)
    end

    # ─── notification digest (skip_webhook + one WebhookDigest.call) ─────────

    it "does not enqueue an individual webhook delivery job per release (digested instead)" do
      release_in(10)
      expect { run! }.not_to have_enqueued_job(NotificationWebhookDeliverJob)
    end

    it "still creates the in-app Notification records even though the per-record webhook is skipped" do
      release_in(5, game: create(:game, title: "Game Soon"))
      release_in(12, game: create(:game, title: "Game Later"))
      expect { run! }.to change(Notification, :count).by(2)
    end

    it "sends ONE WebhookDigest.call with a [countdown, title] row per due release, soonest first" do
      release_in(12, game: create(:game, title: "Game Later"))
      release_in(5, game: create(:game, title: "Game Soon"))

      allow(Pito::Notifications::WebhookDigest).to receive(:call)

      run!

      expect(Pito::Notifications::WebhookDigest).to have_received(:call).once.with(
        title:  "🎮 Upcoming releases",
        accent: Pito::Notifications::WebhookDigest::RELEASES,
        rows:   [ [ "in 5 days", "Game Soon" ], [ "in 12 days", "Game Later" ] ]
      )
    end
  end
end
