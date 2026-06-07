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

    it "each provider's to_h carries :requests_24h and :requests_month keys" do
      [ Pito::Stack::Voyage, Pito::Stack::Youtube, Pito::Stack::Igdb ].each do |mod|
        expect(mod.to_h.keys).to contain_exactly(:requests_24h, :requests_month)
      end
    end
  end

  describe ".track" do
    it "records an ApiRequest and does not raise" do
      expect { Pito::Stack.track("voyage", endpoint: "embed", units: 1) }.not_to raise_error
    end

    it "rescues StandardError so a failing record write never raises to the caller" do
      allow(ApiRequest).to receive(:record!).and_raise(StandardError, "DB down")
      expect { Pito::Stack.track("voyage") }.not_to raise_error
    end
  end
end
