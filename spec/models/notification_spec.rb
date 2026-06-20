# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notification, type: :model do
  describe "validations" do
    it "is valid with a message" do
      expect(build(:notification)).to be_valid
    end

    it "is invalid without a message" do
      expect(build(:notification, message: nil)).not_to be_valid
    end

    it "is invalid with a blank message" do
      expect(build(:notification, message: "")).not_to be_valid
    end

    it "defaults level to info" do
      expect(create(:notification).level).to eq("info")
    end

    it "accepts the known levels" do
      Notification::LEVELS.each { |lvl| expect(build(:notification, level: lvl)).to be_valid }
    end

    it "rejects an unknown level" do
      expect(build(:notification, level: "critical")).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:unread1) { create(:notification, created_at: 1.hour.ago) }
    let!(:unread2) { create(:notification, created_at: 2.hours.ago) }
    let!(:read_one) { create(:notification, :read, created_at: 3.hours.ago) }

    describe ".unread" do
      it "returns only notifications with read_at nil" do
        expect(Notification.unread).to contain_exactly(unread1, unread2)
      end

      it "excludes read notifications" do
        expect(Notification.unread).not_to include(read_one)
      end
    end

    describe ".recent" do
      it "orders newest first" do
        ids = Notification.recent.pluck(:id)
        expect(ids).to eq([ unread1.id, unread2.id, read_one.id ])
      end
    end
  end

  describe "predicates" do
    it "#read? returns false when read_at is nil" do
      n = build(:notification)
      expect(n.read?).to be false
    end

    it "#read? returns true when read_at is set" do
      n = build(:notification, :read)
      expect(n.read?).to be true
    end

    it "#unread? is the inverse of read?" do
      unread = build(:notification)
      read   = build(:notification, :read)
      expect(unread.unread?).to be true
      expect(read.unread?).to be false
    end
  end

  describe "#mark_read!" do
    it "sets read_at to the current time" do
      n = create(:notification)
      before = Time.current
      n.mark_read!
      expect(n.reload.read_at).to be >= before
    end

    it "persists the change" do
      n = create(:notification)
      n.mark_read!
      expect(n.reload.read?).to be true
    end

    it "is idempotent (calling twice does not raise)" do
      n = create(:notification)
      n.mark_read!
      expect { n.mark_read! }.not_to raise_error
    end
  end

  describe "webhook delivery callback" do
    it "enqueues NotificationWebhookDeliverJob after create commit" do
      expect {
        create(:notification)
      }.to have_enqueued_job(NotificationWebhookDeliverJob)
        .with(a_kind_of(Integer))
    end

    it "passes the persisted record id to the job" do
      notification = nil
      expect {
        notification = create(:notification)
      }.to have_enqueued_job(NotificationWebhookDeliverJob)
        .with { |id| expect(id).to eq(notification.id) }
    end
  end

  describe "#mark_unread!" do
    it "clears read_at" do
      n = create(:notification, :read)
      n.mark_unread!
      expect(n.reload.read_at).to be_nil
    end

    it "makes #read? false" do
      n = create(:notification, :read)
      n.mark_unread!
      expect(n.reload.read?).to be false
    end

    it "is idempotent (calling twice does not raise)" do
      n = create(:notification)
      n.mark_unread!
      expect { n.mark_unread! }.not_to raise_error
    end
  end

  describe "live mini-status broadcast on create" do
    it "broadcasts a pito-mini-status replace to pito:global so open windows update without a refresh" do
      expect { create(:notification) }
        .to have_broadcasted_to("pito:global").with { |msg|
          html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
          expect(html).to include("pito-mini-status")
        }
    end
  end
end
