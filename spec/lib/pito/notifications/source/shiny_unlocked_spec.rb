# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::ShinyUnlocked do
  include ActiveJob::TestHelper

  describe ".report!" do
    context "skip_webhook (default false — real-time callers keep their own webhook)" do
      let(:video)       { create(:video, title: "Speed Run") }
      let(:achievement) { create(:achievement, achievable: video, metric: "views", threshold: 1_000) }

      it "enqueues the individual webhook delivery job by default" do
        expect { described_class.report!(achievement) }
          .to have_enqueued_job(NotificationWebhookDeliverJob)
      end

      it "does not enqueue the individual webhook delivery job when skip_webhook: true" do
        expect { described_class.report!(achievement, skip_webhook: true) }
          .not_to have_enqueued_job(NotificationWebhookDeliverJob)
      end

      it "still creates the in-app Notification record when skip_webhook: true" do
        expect { described_class.report!(achievement, skip_webhook: true) }
          .to change(Notification, :count).by(1)
        expect(Notification.last.level).to eq("shiny")
      end
    end

    context "with a Video achievable (general steps key)" do
      let(:video)       { create(:video, title: "Speed Run") }
      let(:achievement) { create(:achievement, achievable: video, metric: "views", threshold: 1_000) }

      it "creates a Notification with level 'shiny'" do
        expect { described_class.report!(achievement) }.to change(Notification, :count).by(1)
        expect(Notification.last.level).to eq("shiny")
      end

      it "includes the video title as the entity name" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("Speed Run")
      end

      it "includes 'earned a shiny'" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("earned a shiny")
      end

      it "includes the witty step name from pito.copy.shinies.steps" do
        described_class.report!(achievement)
        witty = Pito::Copy.render("pito.copy.shinies.steps.1000")
        expect(Notification.last.message).to include(witty)
      end

      it "includes the compact count and plural label for threshold > 1" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("1K")
        expect(Notification.last.message).to include("Views")
      end

      it "uses the general steps key, not steps_game, for a Video" do
        described_class.report!(achievement)
        video_witty = Pito::Copy.render("pito.copy.shinies.steps.1000")
        game_witty  = Pito::Copy.render("pito.copy.shinies.steps_game.1000")
        expect(Notification.last.message).to include(video_witty)
        expect(Notification.last.message).not_to include(game_witty) if video_witty != game_witty
      end

      context "when threshold is 1 (singular label)" do
        let(:achievement) { create(:achievement, achievable: video, metric: "views", threshold: 1) }

        it "uses the singular label in the message" do
          described_class.report!(achievement)
          expect(Notification.last.message).to include("1 View")
          expect(Notification.last.message).not_to include("Views")
        end
      end
    end

    context "with a Game achievable (steps_game key)" do
      let(:game)        { create(:game, title: "Hollow Knight") }
      let(:achievement) { create(:achievement, achievable: game, metric: "views", threshold: 1_000) }

      it "creates a Notification with level 'shiny'" do
        expect { described_class.report!(achievement) }.to change(Notification, :count).by(1)
        expect(Notification.last.level).to eq("shiny")
      end

      it "includes the game title as the entity name" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("Hollow Knight")
      end

      it "includes the witty step name from pito.copy.shinies.steps_game" do
        described_class.report!(achievement)
        witty = Pito::Copy.render("pito.copy.shinies.steps_game.1000")
        expect(Notification.last.message).to include(witty)
      end

      it "uses steps_game, not steps, for a Game" do
        described_class.report!(achievement)
        game_witty  = Pito::Copy.render("pito.copy.shinies.steps_game.1000")
        video_witty = Pito::Copy.render("pito.copy.shinies.steps.1000")
        expect(Notification.last.message).to include(game_witty)
        expect(Notification.last.message).not_to include(video_witty) if game_witty != video_witty
      end

      it "includes the compact count and plural label for threshold > 1" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("1K")
        expect(Notification.last.message).to include("Views")
      end

      context "when threshold is 1 (singular label)" do
        let(:achievement) { create(:achievement, achievable: game, metric: "likes", threshold: 1) }

        it "uses the singular label in the message" do
          described_class.report!(achievement)
          expect(Notification.last.message).to include("1 Like")
          expect(Notification.last.message).not_to include("Likes")
        end
      end
    end

    context "with a Channel achievable (at_handle display, general steps key)" do
      let(:channel)     { create(:channel, handle: "mygamechannel") }
      let(:achievement) { create(:achievement, achievable: channel, metric: "subs", threshold: 1_000) }

      it "uses the at_handle (@handle) as the entity display name" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("@mygamechannel")
      end

      it "uses the general steps key for a Channel" do
        described_class.report!(achievement)
        witty = Pito::Copy.render("pito.copy.shinies.steps.1000")
        expect(Notification.last.message).to include(witty)
      end

      it "includes the plural Subs label for threshold > 1" do
        described_class.report!(achievement)
        expect(Notification.last.message).to include("Subs")
      end

      it "creates a Notification with level 'shiny'" do
        expect { described_class.report!(achievement) }.to change(Notification, :count).by(1)
        expect(Notification.last.level).to eq("shiny")
      end

      context "when threshold is 1 (singular label)" do
        let(:achievement) { create(:achievement, achievable: channel, metric: "subs", threshold: 1) }

        it "uses the singular label in the message" do
          described_class.report!(achievement)
          expect(Notification.last.message).to include("1 Sub")
          expect(Notification.last.message).not_to include("Subs")
        end
      end
    end
  end

  describe ".digest_row" do
    it "returns [witty achievement name, entity display name] for a Video achievable" do
      video       = create(:video, title: "Speed Run")
      achievement = create(:achievement, achievable: video, metric: "views", threshold: 1_000)

      witty = Pito::Copy.render("pito.copy.shinies.steps.1000")
      expect(described_class.digest_row(achievement)).to eq([ witty, "Speed Run" ])
    end

    it "returns [witty achievement name, entity display name] for a Game achievable" do
      game        = create(:game, title: "Hollow Knight")
      achievement = create(:achievement, achievable: game, metric: "views", threshold: 1_000)

      witty = Pito::Copy.render("pito.copy.shinies.steps_game.1000")
      expect(described_class.digest_row(achievement)).to eq([ witty, "Hollow Knight" ])
    end

    it "uses the channel's at_handle as the entity name for a Channel achievable" do
      channel     = create(:channel, handle: "mygamechannel")
      achievement = create(:achievement, achievable: channel, metric: "subs", threshold: 1_000)

      expect(described_class.digest_row(achievement).last).to eq("@mygamechannel")
    end
  end
end
