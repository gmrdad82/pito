# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stack, type: :service do
  describe "provider request counts" do
    before do
      ApiRequest.record!(provider: "voyage")
      ApiRequest.create!(provider: "voyage", created_at: 40.days.ago)
      ApiRequest.record!(provider: "igdb")
      ApiRequest.record!(provider: "youtube")
    end

    it "counts 24h per provider" do
      expect(Pito::Stack::Voyage.requests_24h).to eq(1)
      expect(Pito::Stack::Igdb.requests_24h).to eq(1)
      expect(Pito::Stack::Youtube.requests_24h).to eq(1)
    end

    it "counts the current month per provider" do
      expect(Pito::Stack::Voyage.requests_month).to be >= 1
    end

    it "exposes a providers summary hash" do
      summary = described_class.providers
      expect(summary.keys).to contain_exactly(:voyage, :youtube, :igdb)
      expect(summary[:voyage]).to eq(requests_24h: 1, requests_month: Pito::Stack::Voyage.requests_month)
    end
  end
end
