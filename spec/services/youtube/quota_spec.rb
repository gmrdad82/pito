require "rails_helper"

RSpec.describe Youtube::Quota do
  describe "COSTS" do
    it "is frozen" do
      expect(described_class::COSTS).to be_frozen
    end

    it "pins channels.list to 1 unit" do
      expect(described_class::COSTS["channels.list"]).to eq(1)
    end

    it "pins search.list to 100 units (the expensive one)" do
      expect(described_class::COSTS["search.list"]).to eq(100)
    end
  end

  describe ".cost_for" do
    it "returns the documented cost" do
      expect(described_class.cost_for("channels.list")).to eq(1)
      expect(described_class.cost_for("videos.list")).to eq(1)
      expect(described_class.cost_for("reports.query")).to eq(1)
    end

    it "raises UnknownEndpointError for an unknown endpoint" do
      expect {
        described_class.cost_for("does.not.exist")
      }.to raise_error(Youtube::UnknownEndpointError)
    end
  end

  describe ".budget_remaining" do
    it "returns the daily budget when no calls have been made" do
      identity = create(:google_identity)
      expect(described_class.budget_remaining(identity))
        .to eq(described_class.daily_budget_units)
    end

    it "subtracts today's oauth units for the given identity" do
      identity = create(:google_identity)
      create(:youtube_api_call, google_identity: identity, units: 100, client_kind: "oauth")
      create(:youtube_api_call, google_identity: identity, units: 50, client_kind: "oauth")

      expect(described_class.budget_remaining(identity))
        .to eq(described_class.daily_budget_units - 150)
    end

    it "ignores public-client units (separate bucket)" do
      identity = create(:google_identity)
      create(:youtube_api_call, google_identity: identity, units: 100, client_kind: "oauth")
      create(:youtube_api_call, google_identity: nil, units: 9999, client_kind: "public")

      expect(described_class.budget_remaining(identity))
        .to eq(described_class.daily_budget_units - 100)
    end

    it "ignores rows for other identities" do
      identity = create(:google_identity)
      other = create(:google_identity, google_subject_id: "other-subject-id-99",
                                        email: "other@example.test")
      create(:youtube_api_call, google_identity: other, units: 500, client_kind: "oauth")

      expect(described_class.budget_remaining(identity))
        .to eq(described_class.daily_budget_units)
    end
  end
end
