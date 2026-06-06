# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupNotificationsJob do
  describe "#perform" do
    let!(:old_read) do
      create(:notification, read_at: 8.days.ago)  # read > 7 days ago — should be deleted
    end

    let!(:exactly_cutoff) do
      create(:notification, read_at: 7.days.ago - 1.minute)  # just over 7 days — should be deleted
    end

    let!(:recently_read) do
      create(:notification, read_at: 6.days.ago)  # read < 7 days ago — should be kept
    end

    let!(:unread) do
      create(:notification, read_at: nil)  # never read — should always be kept
    end

    subject(:job) { described_class.new }

    it "deletes notifications read more than 7 days ago" do
      expect { job.perform }
        .to change { Notification.where(id: old_read.id).count }.from(1).to(0)
        .and change { Notification.where(id: exactly_cutoff.id).count }.from(1).to(0)
    end

    it "keeps unread notifications" do
      job.perform
      expect(Notification.exists?(unread.id)).to be true
    end

    it "keeps notifications read less than 7 days ago" do
      job.perform
      expect(Notification.exists?(recently_read.id)).to be true
    end

    it "returns the count of deleted notifications" do
      result = job.perform
      expect(result).to eq(2)
    end

    it "is a no-op when there are no stale read notifications" do
      old_read.destroy
      exactly_cutoff.destroy

      expect { job.perform }.not_to(change { Notification.count })
    end

    it "deletes notifications read EXACTLY at the 7-day cutoff" do
      # read_at: exactly 7.days.ago — on the boundary, so the inclusive
      # `..cutoff` range captures it and it IS deleted.
      exactly_7 = create(:notification, read_at: 7.days.ago)
      job.perform
      expect(Notification.exists?(exactly_7.id)).to be false
    end

    it "keeps notifications read 1 second inside the 7-day window" do
      just_inside = create(:notification, read_at: 7.days.ago + 1.second)
      job.perform
      expect(Notification.exists?(just_inside.id)).to be true
    end

    it "logs the deleted count" do
      expect(Rails.logger).to receive(:info)
        .with(/CleanupNotificationsJob: deleted 2 read notifications/)
      job.perform
    end
  end
end
