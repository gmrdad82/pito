require "rails_helper"

RSpec.describe Voyage::Stats do
  def stub_voyage_credentials_key(value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:voyage, :api_key).and_return(value)
  end

  describe ".call" do
    subject(:stats) { described_class.call }

    before { stub_voyage_credentials_key("vk_test") }

    it "returns every documented key in the hash" do
      expect(stats.keys).to include(
        :configured,
        :model,
        :embedded_games_count,
        :total_games_count,
        :coverage_pct,
        :last_indexed_at,
        :embedded_bundles_count,
        :total_bundles_count,
        :bundle_coverage_pct,
        :storage_kb,
        :embeddings_last_24h
      )
    end

    it "surfaces the locked Voyage model identifier" do
      expect(stats[:model]).to eq(Voyage::Client::DEFAULT_MODEL)
    end

    it "delegates `configured` to AppSetting.voyage_configured?" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      expect(described_class.call[:configured]).to eq(true)

      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      expect(described_class.call[:configured]).to eq(false)
    end

    it "returns coverage_pct as 0 (integer) when the games corpus is empty" do
      Game.delete_all

      expect(stats[:coverage_pct]).to eq(0)
      expect(stats[:coverage_pct]).to be_a(Integer)
    end

    context "with mixed embedded / unembedded games" do
      before do
        Game.delete_all
        Bundle.delete_all
        # 3 games total — 2 embedded
        create(:game, summary_embedding: Array.new(1024) { 0.1 })
        create(:game, summary_embedding: Array.new(1024) { 0.2 })
        create(:game, summary_embedding: nil)
      end

      it "counts embedded games versus total" do
        expect(stats[:embedded_games_count]).to eq(2)
        expect(stats[:total_games_count]).to eq(3)
      end

      it "rounds coverage_pct to an integer (no decimals) — 2/3 = 67" do
        expect(stats[:coverage_pct]).to eq(67)
        expect(stats[:coverage_pct]).to be_a(Integer)
      end

      it "uses .round (not .round(1)) — no fractional digit precision" do
        # 50% rounds to 50, not 50.0 — Integer typed
        Game.delete_all
        create(:game, summary_embedding: Array.new(1024) { 0.1 })
        create(:game, summary_embedding: nil)

        expect(described_class.call[:coverage_pct]).to eq(50)
        expect(described_class.call[:coverage_pct]).to be_a(Integer)
      end

      it "stamps last_indexed_at from the maximum updated_at among embedded rows" do
        expect(stats[:last_indexed_at]).to be_within(2.seconds).of(Time.current)
      end
    end

    context "with mixed embedded / unembedded bundles" do
      before do
        Bundle.delete_all
        create(:bundle, summary_embedding: Array.new(1024) { 0.1 })
        create(:bundle, summary_embedding: nil)
        create(:bundle, summary_embedding: nil)
        create(:bundle, summary_embedding: nil)
      end

      it "counts embedded bundles versus total" do
        expect(stats[:embedded_bundles_count]).to eq(1)
        expect(stats[:total_bundles_count]).to eq(4)
      end

      it "computes bundle_coverage_pct as an integer (1/4 = 25%)" do
        expect(stats[:bundle_coverage_pct]).to eq(25)
        expect(stats[:bundle_coverage_pct]).to be_a(Integer)
      end
    end

    context "when the bundles table is empty" do
      before { Bundle.delete_all }

      it "returns 0 for bundle_coverage_pct (not nil) since the column exists" do
        expect(stats[:bundle_coverage_pct]).to eq(0)
      end
    end

    context "when the bundle column support flag is false" do
      before do
        allow_any_instance_of(described_class).to receive(:bundle_embedding_supported?).and_return(false)
      end

      it "returns nil for bundles_embedded / bundles_total / bundle_coverage_pct" do
        expect(stats[:embedded_bundles_count]).to be_nil
        expect(stats[:total_bundles_count]).to be_nil
        expect(stats[:bundle_coverage_pct]).to be_nil
      end
    end

    describe "storage_kb" do
      it "is an integer derived from pg_total_relation_size across the HNSW indexes" do
        expect(stats[:storage_kb]).to be_a(Integer)
        expect(stats[:storage_kb]).to be >= 0
      end

      it "queries pg_indexes (not the columns directly)" do
        connection = ActiveRecord::Base.connection
        expect(connection).to receive(:execute).with(/pg_total_relation_size.*pg_indexes/m).and_call_original

        described_class.call
      end

      it "returns nil when the SQL query raises" do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError, "boom")

        expect(described_class.call[:storage_kb]).to be_nil
      end
    end

    describe "embeddings_last_24h" do
      before do
        Game.delete_all
        Bundle.delete_all
      end

      it "counts embedded games + embedded bundles updated within the last 24 hours" do
        create(:game, summary_embedding: Array.new(1024) { 0.1 })
        create(:bundle, summary_embedding: Array.new(1024) { 0.2 })

        expect(stats[:embeddings_last_24h]).to eq(2)
      end

      it "excludes rows updated more than 24 hours ago" do
        old_game = create(:game, summary_embedding: Array.new(1024) { 0.1 })
        old_game.update_columns(updated_at: 25.hours.ago)

        expect(stats[:embeddings_last_24h]).to eq(0)
      end

      it "excludes rows whose embedding is nil even if recently updated" do
        create(:game, summary_embedding: nil)

        expect(stats[:embeddings_last_24h]).to eq(0)
      end

      it "returns 0 when the underlying count query raises (rescue path)" do
        instance = described_class.new
        # Force the recent-count chain to raise; rescue should swallow to 0.
        scope = double("scope")
        allow(scope).to receive(:where).and_raise(StandardError, "boom")
        allow(Game).to receive(:where).and_return(scope)
        allow(scope).to receive(:not).and_return(scope)

        expect(instance.send(:compute_recent_count)).to eq(0)
      end
    end
  end
end
