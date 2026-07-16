# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stack, type: :service do
  describe "provider request counts" do
    before do
      ApiRequest.record!(provider: "igdb")
      ApiRequest.create!(provider: "igdb", created_at: 40.days.ago)
      ApiRequest.record!(provider: "youtube")
    end

    it "counts 24h per provider" do
      expect(Pito::Stack::Igdb.requests_24h).to eq(1)
      expect(Pito::Stack::Youtube.requests_24h).to eq(1)
    end

    it "counts the current month per provider" do
      expect(Pito::Stack::Igdb.requests_month).to be >= 1
    end

    it "exposes a providers summary hash" do
      summary = described_class.providers
      expect(summary.keys).to contain_exactly(:youtube, :igdb)
      expect(summary[:igdb]).to eq(requests_24h: 1, requests_month: Pito::Stack::Igdb.requests_month)
    end

    it "each provider's to_h carries :requests_24h and :requests_month keys" do
      [ Pito::Stack::Youtube, Pito::Stack::Igdb ].each do |mod|
        expect(mod.to_h.keys).to contain_exactly(:requests_24h, :requests_month)
      end
    end
  end

  describe ".track" do
    it "records an ApiRequest and does not raise" do
      expect { Pito::Stack.track("igdb", endpoint: "games", units: 1) }.not_to raise_error
    end

    it "rescues StandardError so a failing record write never raises to the caller" do
      allow(ApiRequest).to receive(:record!).and_raise(StandardError, "DB down")
      expect { Pito::Stack.track("igdb") }.not_to raise_error
    end

    # Regression: `.track` rescues StandardError, so an ApiRequest::PROVIDERS
    # whitelist that's out of sync with a real chokepoint's provider string
    # made `create!` raise RecordInvalid *silently* — not_to raise_error above
    # would still pass with zero rows written. Assert the row actually lands
    # for every provider string a real instrumentation shim calls .track with
    # (Game::Igdb::Client, Channel::Youtube::Auditor,
    # Pito::Embedding::Client, Pito::Nl::CompletionClient, Ai::Wire::*).
    it "persists a row for every provider a real chokepoint calls .track with" do
      %w[igdb youtube embedding nlmapper ai].each do |provider|
        expect {
          Pito::Stack.track(provider, endpoint: "test", units: 1)
        }.to change(ApiRequest, :count).by(1)

        expect(ApiRequest.last.provider).to eq(provider)
      end
    end
  end
end
