# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrivateReminderJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  def run!
    described_class.new.perform
  end

  # A private, unscheduled video uploaded `age` ago (D2: privacy private,
  # no future publish_at — the `private_unscheduled` scope).
  def stale_private(age = 2.days)
    create(:video, :private, published_at: age.ago)
  end

  describe "#perform" do
    it "creates a notification for a private vid uploaded more than a day ago" do
      stale_private(2.days)
      expect { run! }.to change(Notification, :count).by(1)
    end

    it "does not count a private vid uploaded less than a day ago" do
      stale_private(12.hours)
      expect { run! }.not_to change(Notification, :count)
    end

    it "does not count a scheduled private vid (future publish_at)" do
      create(:video, :scheduled, published_at: 2.days.ago)
      expect { run! }.not_to change(Notification, :count)
    end

    it "does not count a public vid" do
      create(:video, :public, published_at: 2.days.ago)
      expect { run! }.not_to change(Notification, :count)
    end

    it "does not count an unlisted vid" do
      create(:video, :unlisted, published_at: 2.days.ago)
      expect { run! }.not_to change(Notification, :count)
    end

    it "creates nothing when there are no qualifying vids" do
      expect { run! }.not_to change(Notification, :count)
    end

    it "does not duplicate a same-day re-run" do
      stale_private(2.days)
      run!
      stale_private(3.days)
      expect { run! }.not_to change(Notification, :count)
    end

    it "reminds again once the calendar day rolls over" do
      stale_private(2.days)
      run!

      travel_to(1.day.from_now) do
        stale_private(2.days)
        expect { run! }.to change(Notification, :count).by(1)
      end
    end

    it "counts every qualifying vid into one reminder, not one per vid" do
      stale_private(2.days)
      stale_private(5.days)
      expect { run! }.to change(Notification, :count).by(1)
    end
  end

  describe "webhook fan-out" do
    let(:slack_url)   { "https://hooks.slack.test/abc" }
    let(:discord_url) { "https://discord.test/webhook" }

    before do
      AppSetting.slack_webhook_url   = slack_url
      AppSetting.discord_webhook_url = discord_url
      stub_request(:post, slack_url).to_return(status: 200, body: "ok")
      stub_request(:post, discord_url).to_return(status: 204, body: "")
    end

    it "auto-fans the notification out to Slack + Discord (Notification#after_create_commit)" do
      stale_private(2.days)

      expect { run! }.to have_enqueued_job(NotificationWebhookDeliverJob)

      perform_enqueued_jobs

      expect(a_request(:post, slack_url)).to have_been_made.once
      expect(a_request(:post, discord_url)).to have_been_made.once
    end

    it "hits neither webhook when there is nothing to report" do
      run!

      perform_enqueued_jobs

      expect(a_request(:post, slack_url)).not_to have_been_made
      expect(a_request(:post, discord_url)).not_to have_been_made
    end
  end
end
