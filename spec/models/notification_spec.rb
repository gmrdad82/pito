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
end
