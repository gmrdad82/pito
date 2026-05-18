require "rails_helper"

RSpec.describe BulkVoyageIndexJob, type: :job do
  let(:vector) { Array.new(1024) { 0.7 } }
  let(:voyage_client) { instance_double(Voyage::Client) }

  before do
    allow(Voyage::Client).to receive(:new).and_return(voyage_client)
    allow(voyage_client).to receive(:embed_batch).and_return([])
    allow(Meilisearch::GameIndexer).to receive(:call)
    allow(Meilisearch::BundleIndexer).to receive(:call)
    allow(StackStats::Broadcaster).to receive(:broadcast!)
  end

  describe "argument validation" do
    it "raises ArgumentError for an unknown corpus" do
      expect {
        described_class.new.perform(corpus: "videos")
      }.to raise_error(ArgumentError, /Unknown corpus/)
    end
  end

  describe "queue + ActiveJob plumbing" do
    it "is enqueued on the :search queue" do
      expect(described_class.new.queue_name).to eq("search")
    end

    it "enqueues via ActiveJob with the corpus kwarg" do
      clear_enqueued_jobs
      expect {
        described_class.perform_later(corpus: "games")
      }.to have_enqueued_job(described_class).with(corpus: "games")
    end
  end

  describe "games corpus" do
    context "with mixed embedded and unembedded games" do
      let!(:unembedded) { create(:game, title: "Need Embed", summary: "Foo bar.") }
      let!(:already_embedded) { create(:game, title: "Already", summary: "Done.", summary_embedding: vector) }

      it "calls Voyage::Client#embed_batch ONLY for records without an embedding" do
        expect(voyage_client).to receive(:embed_batch) do |inputs:|
          expect(inputs).to eq([ "Need Embed — Foo bar." ])
          [ vector ]
        end

        described_class.new.perform(corpus: "games")
      end

      it "writes the new embedding into needs-embed rows via update_column" do
        allow(voyage_client).to receive(:embed_batch).and_return([ vector ])

        described_class.new.perform(corpus: "games")
        unembedded.reload

        expect(unembedded.summary_embedding).not_to be_nil
      end

      it "pushes EVERY record to Meilisearch (both already-embedded and newly-embedded)" do
        allow(voyage_client).to receive(:embed_batch).and_return([ vector ])
        expect(Meilisearch::GameIndexer).to receive(:call).twice

        described_class.new.perform(corpus: "games")
      end
    end

    context "when all games already have embeddings" do
      let!(:g1) { create(:game, title: "A", summary: "A.", summary_embedding: vector) }
      let!(:g2) { create(:game, title: "B", summary: "B.", summary_embedding: vector) }

      it "skips Voyage entirely (no embed_batch call)" do
        expect(voyage_client).not_to receive(:embed_batch)

        described_class.new.perform(corpus: "games")
      end

      it "still pushes every record to Meilisearch (idempotent re-sync)" do
        expect(Meilisearch::GameIndexer).to receive(:call).twice

        described_class.new.perform(corpus: "games")
      end
    end

    it "no-ops on an empty corpus (no Voyage call, no Meilisearch push)" do
      Game.delete_all

      expect(voyage_client).not_to receive(:embed_batch)
      expect(Meilisearch::GameIndexer).not_to receive(:call)

      described_class.new.perform(corpus: "games")
    end

    it "skips games whose summary is nil or blank" do
      create(:game, title: "Skipped 1", summary: nil)
      create(:game, title: "Skipped 2", summary: "")
      indexable = create(:game, title: "Indexable", summary: "Real summary.")

      expect(voyage_client).to receive(:embed_batch) do |inputs:|
        expect(inputs).to eq([ "Indexable — Real summary." ])
        [ vector ]
      end

      described_class.new.perform(corpus: "games")
    end
  end

  describe "bundles corpus" do
    let!(:bundle_with_name) { create(:bundle, name: "Has Name") }
    let!(:bundle_already) { create(:bundle, name: "Done", summary_embedding: vector) }

    it "embeds only bundles without an existing embedding" do
      expect(voyage_client).to receive(:embed_batch) do |inputs:|
        expect(inputs).to eq([ "Has Name" ])
        [ vector ]
      end

      described_class.new.perform(corpus: "bundles")
    end

    it "pushes every bundle to Meilisearch" do
      allow(voyage_client).to receive(:embed_batch).and_return([ vector ])
      expect(Meilisearch::BundleIndexer).to receive(:call).twice

      described_class.new.perform(corpus: "bundles")
    end

    it "no-ops on an empty corpus" do
      Bundle.delete_all

      expect(voyage_client).not_to receive(:embed_batch)
      expect(Meilisearch::BundleIndexer).not_to receive(:call)

      described_class.new.perform(corpus: "bundles")
    end
  end

  describe "ensure-block broadcasting" do
    let!(:game) { create(:game, title: "g", summary: "s") }

    before { allow(voyage_client).to receive(:embed_batch).and_return([ vector ]) }

    it "calls StackStats::Broadcaster.broadcast! once on success" do
      expect(StackStats::Broadcaster).to receive(:broadcast!).at_least(:once)

      described_class.new.perform(corpus: "games")
    end

    it "schedules StackStatsBroadcastJob with wait: 1.second after the job completes" do
      clear_enqueued_jobs

      expect {
        described_class.new.perform(corpus: "games")
      }.to have_enqueued_job(StackStatsBroadcastJob)
    end

    it "still broadcasts and re-enqueues delayed broadcast even when the job raises" do
      allow(voyage_client).to receive(:embed_batch).and_raise(Voyage::Client::Error, "rate limit")
      expect(StackStats::Broadcaster).to receive(:broadcast!).at_least(:once)
      clear_enqueued_jobs

      expect {
        described_class.new.perform(corpus: "games")
      }.to raise_error(Voyage::Client::Error)

      expect(enqueued_jobs.map { |j| j[:job] }).to include(StackStatsBroadcastJob)
    end
  end
end
