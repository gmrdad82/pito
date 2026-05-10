require "rails_helper"

# Phase 16 §3 UX restructure 2026-05-10 — read-notification cleanup.
RSpec.describe NotificationCleanupJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  describe "#perform" do
    it "deletes read notifications older than the retention period" do
      stale = travel_to(8.days.ago) { create(:notification, :read, :video_published) }
      described_class.new.perform
      expect(Notification.where(id: stale.id)).not_to exist
    end

    it "does NOT delete read notifications inside the retention window" do
      fresh = create(:notification, :read, :video_published)
      # `:read` trait stamps `in_app_read_at = 1.minute.ago` — well inside
      # the 7-day window.
      described_class.new.perform
      expect(Notification.where(id: fresh.id)).to exist
    end

    it "does NOT delete unread notifications even if they're old" do
      old_unread = travel_to(30.days.ago) { create(:notification, :video_published) }
      described_class.new.perform
      expect(Notification.where(id: old_unread.id)).to exist
    end

    it "returns the number of rows deleted" do
      travel_to(8.days.ago) { create_list(:notification, 3, :read, :video_published) }
      expect(described_class.new.perform).to eq(3)
    end

    it "is a no-op when there are no stale read notifications" do
      create(:notification, :video_published) # unread
      create(:notification, :read, :video_published) # fresh-read
      expect(described_class.new.perform).to eq(0)
    end

    it "logs the deletion count" do
      travel_to(8.days.ago) { create(:notification, :read, :video_published) }
      expect(Rails.logger).to receive(:info).with(/deleted 1 read notification/)
      described_class.new.perform
    end

    it "uses the documented retention period (7 days)" do
      expect(described_class::RETENTION_PERIOD).to eq(7.days)
    end

    it "deletes a row whose in_app_read_at sits just past the cutoff" do
      stale = create(:notification, :video_published)
      stale.update_column(:in_app_read_at, 7.days.ago - 1.second)
      described_class.new.perform
      expect(Notification.where(id: stale.id)).not_to exist
    end

    it "skips a row whose in_app_read_at sits just inside the cutoff" do
      borderline = create(:notification, :video_published)
      borderline.update_column(:in_app_read_at, 7.days.ago + 1.minute)
      described_class.new.perform
      expect(Notification.where(id: borderline.id)).to exist
    end
  end

  describe "Sidekiq cron registration" do
    it "is registered in config/sidekiq_cron.yml under `notification_cleanup`" do
      cron_yaml = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
      expect(cron_yaml).to have_key("notification_cleanup")
      expect(cron_yaml["notification_cleanup"]).to include("class" => "NotificationCleanupJob")
    end

    it "is configured for daily execution" do
      cron_yaml = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
      # Match a daily cron expression — minute hour * * *.
      expect(cron_yaml["notification_cleanup"]["cron"]).to match(/\A\d+ \d+ \* \* \*\z/)
    end
  end
end
