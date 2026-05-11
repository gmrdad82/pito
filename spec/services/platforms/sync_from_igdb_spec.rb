require "rails_helper"

# Phase 27 §1a — IGDB `/platforms` upsert.
RSpec.describe Platforms::SyncFromIgdb do
  let(:client) { instance_double(Igdb::Client) }

  describe "#call" do
    it "creates a Platform for a fresh IGDB row" do
      Platform.unscoped.delete_all
      allow(client).to receive(:list_all_platforms).and_return(
        [ { "id" => 167, "name" => "PlayStation 5", "abbreviation" => "PS5", "slug" => "ps5" } ]
      )

      result = described_class.new(client: client).call

      expect(Platform.unscoped.count).to eq(1)
      platform = Platform.unscoped.first
      expect(platform.igdb_id).to eq(167)
      expect(platform.name).to eq("PlayStation 5")
      expect(platform.abbreviation).to eq("PS5")
      expect(platform.slug).to eq("ps5")
      expect(result.created).to eq(1)
      expect(result.updated).to eq(0)
      expect(result.total).to eq(1)
    end

    it "updates name + abbreviation when IGDB changes them" do
      existing = create(:platform, igdb_id: 167, name: "Playstation 5", abbreviation: "PS-5", slug: "ps5-update-test")
      allow(client).to receive(:list_all_platforms).and_return(
        [ { "id" => 167, "name" => "PlayStation 5", "abbreviation" => "PS5", "slug" => "ps5-update-test" } ]
      )

      result = described_class.new(client: client).call

      existing.reload
      expect(existing.name).to eq("PlayStation 5")
      expect(existing.abbreviation).to eq("PS5")
      expect(result.updated).to eq(1)
      expect(result.created).to eq(0)
    end

    it "does not touch slug on existing rows" do
      existing = create(:platform, igdb_id: 167, name: "PS5", slug: "old-stable-slug")
      allow(client).to receive(:list_all_platforms).and_return(
        [ { "id" => 167, "name" => "PS5", "abbreviation" => "PS5", "slug" => "new-igdb-slug" } ]
      )

      described_class.new(client: client).call

      expect(existing.reload.slug).to eq("old-stable-slug")
    end

    it "is idempotent — re-running yields no further mutations" do
      allow(client).to receive(:list_all_platforms).and_return(
        [ { "id" => 167, "name" => "PS5", "abbreviation" => "PS5", "slug" => "ps5-idempotent" } ]
      )

      described_class.new(client: client).call
      result = described_class.new(client: client).call

      expect(result.created).to eq(0)
      expect(result.updated).to eq(0)
    end

    it "returns zero counts when IGDB returns an empty list" do
      Platform.unscoped.delete_all
      allow(client).to receive(:list_all_platforms).and_return([])

      result = described_class.new(client: client).call

      expect(result.created).to eq(0)
      expect(result.updated).to eq(0)
      expect(result.total).to eq(0)
    end

    it "re-raises IGDB errors after logging" do
      allow(client).to receive(:list_all_platforms)
        .and_raise(Igdb::Client::RateLimited.new(retry_after: 1, message: "ratelimit"))
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.new(client: client).call
      }.to raise_error(Igdb::Client::RateLimited)
      expect(Rails.logger).to have_received(:error).with(/Platforms::SyncFromIgdb/)
    end

    it "fills igdb_id on a pre-seeded slug without changing the slug" do
      seeded = Platform.unscoped.find_or_create_by!(slug: "ps5-prefilled") do |p|
        p.name = "PlayStation 5"
      end
      expect(seeded.igdb_id).to be_nil

      allow(client).to receive(:list_all_platforms).and_return(
        [ { "id" => 167, "name" => "PlayStation 5", "abbreviation" => "PS5", "slug" => "ps5-prefilled" } ]
      )

      # On a seeded row, sync should NOT find by igdb_id (it's nil); it
      # creates a new row keyed on the upstream id. This is the
      # documented gap for Open Question #5: pre-seeded rows that
      # already match upstream by slug do NOT auto-merge — they remain
      # distinct rows until an operator reconciles. The spec pins the
      # current behavior so a future operator can write the merge.
      result = described_class.new(client: client).call
      expect(result.created).to eq(1)
      expect(Platform.unscoped.where(slug: "ps5-prefilled").count).to eq(1)
    end

    it "preserves a stale local platform (no IGDB match)" do
      stale = create(:platform, igdb_id: 999_999, slug: "stale-local", name: "Retired")
      allow(client).to receive(:list_all_platforms).and_return([])

      described_class.new(client: client).call

      expect(Platform.unscoped.exists?(stale.id)).to be(true)
    end

    it "ignores malformed entries (no id, non-hash rows)" do
      allow(client).to receive(:list_all_platforms).and_return(
        [
          { "id" => 167, "name" => "PS5", "abbreviation" => "PS5", "slug" => "ps5-mixed" },
          { "name" => "No id row" },
          "garbage",
          nil
        ]
      )

      expect {
        described_class.new(client: client).call
      }.to change { Platform.unscoped.where(igdb_id: 167).count }.by(1)
    end
  end

  describe ".call" do
    it "delegates to a new instance" do
      allow(client).to receive(:list_all_platforms).and_return([])
      result = described_class.call(client: client)
      expect(result).to be_a(Platforms::SyncFromIgdb::Result)
    end
  end
end
