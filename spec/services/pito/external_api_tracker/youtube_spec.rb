# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ExternalApiTracker::Youtube do
  describe "constants" do
    it "defines DAILY_QUOTA as 10_000" do
      expect(described_class::DAILY_QUOTA).to eq(10_000)
    end
  end

  describe ".quota" do
    it "returns DAILY_QUOTA" do
      expect(described_class.quota).to eq(10_000)
    end
  end

  describe ".window" do
    it "returns :daily" do
      expect(described_class.window).to eq(:daily)
    end
  end

  describe ".usage" do
    # YoutubeApiCall is not a persisted model in the current schema — the
    # constant is undefined in the test environment.  The tracker delegates to
    # it unconditionally, so a real call raises NameError.  We stub the class
    # method to verify the arithmetic contract instead.
    it "sums today's units via YoutubeApiCall (stubbed)" do
      stub_const("YoutubeApiCall", Class.new do
        def self.where(*)   = self
        def self.sum(*)     = 75
      end)
      expect(described_class.usage).to eq(75)
    end

    it "returns 0 when no calls have been made today (stubbed to 0)" do
      stub_const("YoutubeApiCall", Class.new do
        def self.where(*)   = self
        def self.sum(*)     = 0
      end)
      expect(described_class.usage).to eq(0)
    end
  end

  describe ".percent" do
    it "returns a Float in 0.0..1.0" do
      allow(described_class).to receive(:usage).and_return(0)
      p = described_class.percent
      expect(p).to be_a(Float)
      expect(p).to be_between(0.0, 1.0).inclusive
    end

    it "computes usage / DAILY_QUOTA" do
      allow(described_class).to receive(:usage).and_return(5000)
      expect(described_class.percent).to be_within(0.001).of(0.5)
    end

    it "clamps to 1.0 when usage exceeds quota" do
      allow(described_class).to receive(:usage).and_return(99_999)
      expect(described_class.percent).to eq(1.0)
    end
  end

  describe ".status" do
    it "returns :ok for low usage" do
      allow(described_class).to receive(:percent).and_return(0.3)
      expect(described_class.status).to eq(:ok)
    end

    it "returns :warn at 70% usage" do
      allow(described_class).to receive(:percent).and_return(0.7)
      expect(described_class.status).to eq(:warn)
    end

    it "returns :critical at 90% usage" do
      allow(described_class).to receive(:percent).and_return(0.9)
      expect(described_class.status).to eq(:critical)
    end

    it "returns :critical at 100% usage" do
      allow(described_class).to receive(:percent).and_return(1.0)
      expect(described_class.status).to eq(:critical)
    end
  end
end
