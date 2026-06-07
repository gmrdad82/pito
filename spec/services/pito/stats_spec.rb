# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stats do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { create(:channel) }

  describe ".get" do
    it "returns the stored value" do
      create(:stat, entity: channel, kind: "views", value: 4_200)
      expect(described_class.get(channel, :views)).to eq(4_200)
    end

    it "returns nil when no row exists" do
      expect(described_class.get(channel, :subscribers)).to be_nil
    end

    it "accepts a string kind" do
      create(:stat, entity: channel, kind: "subscribers", value: 99)
      expect(described_class.get(channel, "subscribers")).to eq(99)
    end

    it "raises on an unknown kind" do
      expect { described_class.get(channel, :bogus) }.to raise_error(ArgumentError)
    end
  end

  describe ".set" do
    it "creates a row and stamps synced_at" do
      freeze_time do
        stat = described_class.set(channel, :views, 1_234)
        expect(stat.value).to eq(1_234)
        expect(stat.synced_at).to eq(Time.current)
      end
    end

    it "upserts an existing row instead of duplicating" do
      described_class.set(channel, :views, 10)
      expect { described_class.set(channel, :views, 20) }
        .not_to change { Stat.where(entity: channel, kind: "views").count }.from(1)
      expect(described_class.get(channel, :views)).to eq(20)
    end

    it "refreshes synced_at on update" do
      first = nil
      travel_to(2.days.ago) { first = described_class.set(channel, :views, 1).synced_at }
      second = described_class.set(channel, :views, 2).synced_at
      expect(second).to be > first
    end

    it "stores a nil value" do
      stat = described_class.set(channel, :views, nil)
      expect(stat.value).to be_nil
      expect(described_class.get(channel, :views)).to be_nil
    end

    it "raises on an unknown kind" do
      expect { described_class.set(channel, :bogus, 1) }.to raise_error(ArgumentError)
    end
  end

  describe ".for" do
    it "returns present counters keyed by kind symbol" do
      described_class.set(channel, :views, 500)
      described_class.set(channel, :subscribers, 50)
      expect(described_class.for(channel)).to eq(views: 500, subscribers: 50)
    end

    it "omits kinds without a row" do
      described_class.set(channel, :views, 7)
      expect(described_class.for(channel)).to eq(views: 7)
    end
  end
end
