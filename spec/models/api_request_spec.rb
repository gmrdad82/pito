# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiRequest, type: :model do
  describe "validations" do
    it "requires a known provider" do
      expect(described_class.new(provider: "voyage")).to be_valid
      expect(described_class.new(provider: "bogus")).not_to be_valid
      expect(described_class.new(provider: nil)).not_to be_valid
    end
  end

  describe ".record!" do
    it "creates a row with created_at set" do
      row = described_class.record!(provider: "igdb", endpoint: "/games", units: 1)
      expect(row).to be_persisted
      expect(row.provider).to eq("igdb")
      expect(row.endpoint).to eq("/games")
      expect(row.created_at).to be_present
    end
  end

  describe "window scopes" do
    before do
      described_class.record!(provider: "voyage")                                  # now
      described_class.create!(provider: "voyage", created_at: 2.days.ago)          # >24h, this month-ish
      described_class.create!(provider: "voyage", created_at: 40.days.ago)         # last month
    end

    it "last_24h counts only the last 24 hours" do
      expect(described_class.voyage.last_24h.count).to eq(1)
    end

    it "this_month counts rows since the start of the month" do
      this_month = described_class.voyage.this_month.count
      expect(this_month).to eq(described_class.voyage.where(created_at: Time.current.beginning_of_month..).count)
      expect(this_month).to be >= 1
    end

    it "for_provider isolates by provider" do
      described_class.record!(provider: "igdb")
      expect(described_class.igdb.count).to eq(1)
      expect(described_class.voyage.count).to eq(3)
    end
  end

  describe ".prune!" do
    it "deletes rows older than the retention window" do
      described_class.create!(provider: "youtube", created_at: 3.months.ago)
      described_class.record!(provider: "youtube")
      expect { described_class.prune! }.to change(described_class, :count).by(-1)
    end
  end
end
