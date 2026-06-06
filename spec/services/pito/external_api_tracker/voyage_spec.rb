# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ExternalApiTracker::Voyage do
  describe ".usage" do
    it "returns an integer (skeleton returns 0)" do
      expect(described_class.usage).to be_a(Integer)
    end
  end

  describe ".quota" do
    it "returns nil (no documented cap in the skeleton)" do
      expect(described_class.quota).to be_nil
    end
  end

  describe ".window" do
    it "returns :monthly" do
      expect(described_class.window).to eq(:monthly)
    end
  end

  describe ".percent" do
    it "returns 0.0 when quota is nil (no cap)" do
      allow(described_class).to receive(:quota).and_return(nil)
      expect(described_class.percent).to eq(0.0)
    end

    it "computes usage/quota when quota is set" do
      allow(described_class).to receive(:usage).and_return(500)
      allow(described_class).to receive(:quota).and_return(1000)
      expect(described_class.percent).to be_within(0.001).of(0.5)
    end

    it "clamps to 1.0 when usage exceeds quota" do
      allow(described_class).to receive(:usage).and_return(9999)
      allow(described_class).to receive(:quota).and_return(100)
      expect(described_class.percent).to eq(1.0)
    end
  end

  describe ".status" do
    it "returns :ok when percent is low" do
      allow(described_class).to receive(:percent).and_return(0.5)
      expect(described_class.status).to eq(:ok)
    end

    it "returns :warn at 0.7" do
      allow(described_class).to receive(:percent).and_return(0.7)
      expect(described_class.status).to eq(:warn)
    end

    it "returns :critical at 0.9" do
      allow(described_class).to receive(:percent).and_return(0.9)
      expect(described_class.status).to eq(:critical)
    end

    it "returns :ok when quota is nil (percent = 0.0)" do
      allow(described_class).to receive(:quota).and_return(nil)
      expect(described_class.status).to eq(:ok)
    end
  end
end
