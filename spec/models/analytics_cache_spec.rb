# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsCache do
  it "has a working factory" do
    expect(build(:analytics_cache)).to be_valid
  end

  describe "validations" do
    it "requires signature" do
      expect(build(:analytics_cache, signature: nil)).not_to be_valid
    end

    it "requires status" do
      expect(build(:analytics_cache, status: nil)).not_to be_valid
    end

    it "rejects a status outside STATUSES" do
      expect(build(:analytics_cache, status: "unknown")).not_to be_valid
    end

    it "accepts each allowed status" do
      AnalyticsCache::STATUSES.each do |s|
        expect(build(:analytics_cache, status: s)).to be_valid
      end
    end

    describe "signature uniqueness" do
      before { create(:analytics_cache, signature: "dupe:sig") }

      it "is invalid when the signature already exists" do
        dup = build(:analytics_cache, signature: "dupe:sig")
        expect(dup).not_to be_valid
        expect(dup.errors[:signature]).to be_present
      end

      it "raises at the DB level when saved with validate: false" do
        dup = build(:analytics_cache, signature: "dupe:sig")
        expect { dup.save(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe "#expired?" do
    it "returns false when expires_at is nil" do
      expect(build(:analytics_cache, expires_at: nil)).not_to be_expired
    end

    it "returns false when expires_at is in the future" do
      expect(build(:analytics_cache, expires_at: 1.minute.from_now)).not_to be_expired
    end

    it "returns true when expires_at is in the past" do
      expect(build(:analytics_cache, expires_at: 1.second.ago)).to be_expired
    end
  end

  describe "#live?" do
    it "returns true for a ready, unexpired row" do
      expect(build(:analytics_cache, :ready)).to be_live
    end

    it "returns false for a ready but expired row" do
      expect(build(:analytics_cache, :expired)).not_to be_live
    end

    it "returns false for a pending row" do
      expect(build(:analytics_cache, status: "pending")).not_to be_live
    end

    it "returns false for a failed row" do
      expect(build(:analytics_cache, :failed)).not_to be_live
    end
  end
end
