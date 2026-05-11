require "rails_helper"

RSpec.describe LoginAttemptGeoEnrichJob do
  describe "#perform" do
    let!(:attempt) { create(:login_attempt) }

    it "happy: row missing geo → looks up via enricher and updates" do
      allow(Auth::GeoEnricher).to receive(:call).with(attempt.ip).and_return(
        city: "Berlin", region: "Berlin", country: "DE"
      )

      described_class.new.perform(attempt.id)

      attempt.reload
      expect(attempt.geo_city).to eq("Berlin")
      expect(attempt.geo_region).to eq("Berlin")
      expect(attempt.geo_country).to eq("DE")
    end

    it "sad: row already has geo → no-op (does not call enricher)" do
      attempt.update!(geo_city: "old", geo_region: "old", geo_country: "ZZ")
      expect(Auth::GeoEnricher).not_to receive(:call)
      described_class.new.perform(attempt.id)
      expect(attempt.reload.geo_country).to eq("ZZ")
    end

    it "sad: row deleted between enqueue and run → no crash" do
      missing_id = attempt.id
      attempt.destroy!
      expect { described_class.new.perform(missing_id) }.not_to raise_error
    end

    it "edge: enricher still misses (DB still missing) → no-op" do
      allow(Auth::GeoEnricher).to receive(:call).and_return(
        city: nil, region: nil, country: nil
      )
      described_class.new.perform(attempt.id)
      expect(attempt.reload.geo_country).to be_nil
    end
  end
end
