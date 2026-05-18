require "rails_helper"

RSpec.describe StackStats::Payload do
  describe ".call" do
    let(:engine) { instance_double(Search::MeilisearchEngine) }

    before do
      allow(Search).to receive(:engine).and_return(engine)
      allow(engine).to receive(:respond_to?).with(:per_index_stats).and_return(true)
      allow(engine).to receive(:per_index_stats).and_return({})
      allow(engine).to receive(:documents_count_for).and_return(0)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
    end

    subject(:payload) { described_class.call }

    it "returns a hash with all 5 documented top-level sections" do
      expect(payload).to be_a(Hash)
      expect(payload.keys).to include(:redis, :voyage, :postgres, :meilisearch, :assets)
    end

    describe "redis section" do
      it "includes the documented sidekiq counter keys" do
        expect(payload[:redis].keys).to include(:busy, :scheduled, :enqueued, :retry, :dead, :processed, :failed)
      end

      it "swallows redis errors to an empty hash (transient blip never blanks pane)" do
        allow(Sidekiq::Stats).to receive(:new).and_raise(StandardError, "redis down")

        expect(described_class.call[:redis]).to eq({})
      end
    end

    describe "voyage section" do
      it "merges Voyage::Stats with a formatted last_indexed_at string" do
        fake_ts = Time.utc(2026, 5, 18, 12, 0, 0)
        allow(Voyage::Stats).to receive(:call).and_return(
          configured: true,
          model: "voyage-3",
          embedded_games_count: 1,
          total_games_count: 1,
          coverage_pct: 100,
          last_indexed_at: fake_ts,
          embedded_bundles_count: 0,
          total_bundles_count: 0,
          bundle_coverage_pct: 0,
          storage_kb: 1024,
          embeddings_last_24h: 1
        )

        expect(payload[:voyage]).to include(
          configured: true,
          model: "voyage-3",
          embedded_games_count: 1,
          coverage_pct: 100
        )
        expect(payload[:voyage]).to have_key(:last_indexed_at_formatted)
      end

      it "returns {} when Voyage::Stats raises" do
        allow(Voyage::Stats).to receive(:call).and_raise(StandardError, "boom")

        expect(described_class.call[:voyage]).to eq({})
      end
    end

    describe "postgres section" do
      it "returns flat per-table `<label>_rows` and `<label>_size_bytes` keys" do
        expect(payload[:postgres].keys).to include(:games_rows, :games_size_bytes, :bundles_rows, :bundles_size_bytes)
      end

      it "returns {} when the connection raises" do
        allow(ActiveRecord::Base).to receive(:connection).and_raise(StandardError, "db down")

        expect(described_class.call[:postgres]).to eq({})
      end
    end

    describe "meilisearch section" do
      context "with a games index present" do
        before do
          allow(engine).to receive(:per_index_stats).and_return(
            "games_development" => { documents: 5, size_bytes: 1024 }
          )
          allow(engine).to receive(:documents_count_for).with("games_development", field: "kind", value: "game").and_return(3)
          allow(engine).to receive(:documents_count_for).with("games_development", field: "kind", value: "bundle").and_return(2)
        end

        it "splits documents into games and bundles via the kind discriminator" do
          expect(payload[:meilisearch][:games_docs]).to eq(3)
          expect(payload[:meilisearch][:bundles_docs]).to eq(2)
          expect(payload[:meilisearch][:games_missing]).to eq(false)
        end

        it "marks bundles with omit_size: true (no per-kind size split available)" do
          expect(payload[:meilisearch][:bundles_omit_size]).to eq(true)
        end
      end

      context "without a games index" do
        before { allow(engine).to receive(:per_index_stats).and_return({}) }

        it "marks games and bundles as missing (zero docs, missing flag set)" do
          expect(payload[:meilisearch][:games_missing]).to eq(true)
          expect(payload[:meilisearch][:bundles_missing]).to eq(true)
          expect(payload[:meilisearch][:games_docs]).to eq(0)
          expect(payload[:meilisearch][:bundles_docs]).to eq(0)
        end
      end

      it "returns {} when the engine raises" do
        allow(engine).to receive(:per_index_stats).and_raise(StandardError, "search down")

        expect(described_class.call[:meilisearch]).to eq({})
      end
    end

    describe "assets section" do
      let(:tmp_root) { Dir.mktmpdir("pito-assets-payload-spec") }

      before do
        @prev = ENV["PITO_ASSETS_PATH"]
        ENV["PITO_ASSETS_PATH"] = tmp_root
        Rails.cache.clear
      end

      after do
        ENV["PITO_ASSETS_PATH"] = @prev
        FileUtils.rm_rf(tmp_root)
      end

      it "returns the documented `<category>_files` / `<category>_size_bytes` keys" do
        expect(payload[:assets].keys).to include(:cover_arts_files, :cover_arts_size_bytes, :composites_files, :composites_size_bytes)
      end

      it "counts files and sums sizes inside the configured asset directories" do
        FileUtils.mkdir_p(File.join(tmp_root, "covers", "games"))
        FileUtils.mkdir_p(File.join(tmp_root, "covers", "bundles"))
        File.write(File.join(tmp_root, "covers", "games", "a.jpg"), "x" * 100)
        File.write(File.join(tmp_root, "covers", "bundles", "b.jpg"), "y" * 50)

        result = described_class.call[:assets]

        expect(result[:cover_arts_files]).to eq(1)
        expect(result[:cover_arts_size_bytes]).to eq(100)
        expect(result[:composites_files]).to eq(1)
        expect(result[:composites_size_bytes]).to eq(50)
      end

      it "returns zeroed file/size keys when the root directory is absent" do
        FileUtils.rm_rf(tmp_root)

        result = described_class.call[:assets]

        expect(result[:cover_arts_files]).to eq(0)
        expect(result[:composites_files]).to eq(0)
      end
    end
  end
end
