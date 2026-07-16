# frozen_string_literal: true

require "rails_helper"

# Coverage map — see lib/pito/nl/router.rb's header for the "three corpora,
# three jobs" contract and the digest-gated materialize/prune/embed cycle
# this spec checks. The embedding sidecar is NEVER hit: every vector below is
# a deterministic one-hot(ish) 768-float array keyed off the exact
# post-normalize text, computed in `vector_for` and served through an
# `instance_double(Pito::Embedding::Client)`. `TARGET_PHRASE` is a real
# tools.yml phrase (the `list` tool's `nl_examples`); every other real-corpus
# phrase collapses onto the shared `junk_vector` so it can never outrank the
# one row a given example cares about.
RSpec.describe Pito::Nl::Router do
  TARGET_PHRASE      = "list me the vids"
  TARGET_TOOL        = :list
  POSITIVE_UTTERANCE = "please list my stuff for me"
  NEGATIVE_UTTERANCE = "zzz nonsense filler chatter"
  SNAP_UTTERANCE     = "list me the clips" # "clips" -> "vids" via Config.nl_synonyms

  let(:client) { instance_double(Pito::Embedding::Client) }

  def one_hot(dim, magnitude = 1.0)
    Array.new(768, 0.0).tap { |vector| vector[dim] = magnitude }
  end

  # Exact match: cosine similarity 1.0 against itself.
  def target_vector
    one_hot(0)
  end

  # Shared by every real-corpus phrase this spec doesn't name — orthogonal to
  # every other vector below, so it never wins a nearest-neighbor query.
  def junk_vector
    one_hot(700)
  end

  # dot(target_vector) = 4, norm = 5 -> cosine similarity 4/(5*1) = 0.8.
  def positive_vector
    one_hot(0, 4.0).tap { |vector| vector[1] = 3.0 }
  end

  # Orthogonal to target_vector and junk_vector alike -> cosine similarity 0.
  def negative_vector
    one_hot(701)
  end

  def vector_for(text)
    case text
    when TARGET_PHRASE      then target_vector
    when POSITIVE_UTTERANCE then positive_vector
    when NEGATIVE_UTTERANCE then negative_vector
    else junk_vector
    end
  end

  before do
    # `.nearest`'s ORDER BY runs through nl_examples' HNSW index, which is an
    # APPROXIMATE nearest-neighbor structure. Across many examples each
    # inserting/embedding the full corpus inside a rolled-back transaction,
    # the graph accumulates dead entries and recall degrades enough to miss
    # the true nearest neighbor (reproduced directly against this test db:
    # an Index Scan plan returned nil where a Seq Scan reliably found
    # TARGET_PHRASE at distance 0.2). Forcing a sequential scan makes the
    # distance computation exact and this spec's assertions deterministic —
    # production non-transactional traffic is unaffected.
    ActiveRecord::Base.connection.execute("SET LOCAL enable_indexscan = off")

    allow(Pito::Embedding::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed) { |texts| texts.map { |text| vector_for(text) } }
  end

  # Independently recomputes the expected materialized corpus straight off
  # Pito::Dispatch::Config — a regression check against ROUTER_EXCLUDED_TOOLS
  # and the `chat:`-membership filter, not a tautology against Router's own
  # (private) `corpus` method.
  def expected_corpus_phrases
    Pito::Dispatch::Config.data.fetch(:tools).flat_map do |name, tool|
      next [] if %w[greet farewell].include?(name.to_s)
      next [] unless tool.key?(:chat)

      Pito::Dispatch::Config.nl_examples(tool: name)
    end
  end

  describe ".sync!" do
    it "materializes one row per unique chat-tool nl_example phrase, excluding greet/farewell" do
      described_class.sync!

      expect(described_class::Example.count).to eq(expected_corpus_phrases.uniq.size)
      expect(described_class::Example.pluck(:tool).uniq).not_to include("greet", "farewell")
    end

    it "gives every materialized row a unique digest" do
      described_class.sync!

      digests = described_class::Example.pluck(:digest)
      expect(digests.uniq.size).to eq(digests.size)
    end

    it "makes no second embed call and keeps the row count stable when the corpus hasn't changed" do
      described_class.sync!
      count_after_first_sync = described_class::Example.count

      expect(client).not_to receive(:embed)
      described_class.sync!

      expect(described_class::Example.count).to eq(count_after_first_sync)
    end

    it "prunes a row whose digest is no longer present in the corpus" do
      described_class.sync!
      stray_digest = Digest::SHA256.hexdigest("a stray fixture phrase absent from tools.yml")
      described_class::Example.create!(
        tool: "list", phrase: "a stray fixture phrase absent from tools.yml", digest: stray_digest
      )

      described_class.sync!

      expect(described_class::Example.where(digest: stray_digest)).not_to exist
    end

    it "never nulls an already-embedded row's vector on re-sync (upsert preserves it)" do
      described_class.sync!
      row = described_class::Example.find_by!(digest: Digest::SHA256.hexdigest(TARGET_PHRASE))
      expect(row.embedding).to eq(target_vector)

      described_class.sync!

      expect(row.reload.embedding).to eq(target_vector)
    end
  end

  describe ".route" do
    before { described_class.sync! }

    it "returns the nearest tool with confidence approximating the cosine similarity" do
      result = described_class.route(POSITIVE_UTTERANCE)

      expect(result[:tool]).to eq(TARGET_TOOL)
      expect(result[:nearest_phrase]).to eq(TARGET_PHRASE)
      expect(result[:confidence]).to be_within(0.0001).of(0.8)
    end

    it "returns nil when the nearest neighbor sits below the suggest floor" do
      expect(described_class.route(NEGATIVE_UTTERANCE)).to be_nil
    end

    it "snaps a synonym token onto its canonical form before matching" do
      result = described_class.route(SNAP_UTTERANCE)

      expect(result[:tool]).to eq(TARGET_TOOL)
      expect(result[:confidence]).to be_within(0.0001).of(1.0)
    end

    it "returns nil for a blank utterance without calling the embedding client" do
      expect(client).not_to receive(:embed)

      expect(described_class.route("")).to be_nil
      expect(described_class.route(nil)).to be_nil
    end

    it "returns nil when the embedder yields nil for the utterance (sidecar down)" do
      allow(client).to receive(:embed).with([ "unreachable phrase" ]).and_return([ nil ])

      expect(described_class.route("unreachable phrase")).to be_nil
    end
  end

  describe "lazy self-heal" do
    it "syncs exactly once from an empty cache, then routes" do
      expect(described_class::Example.count).to eq(0)
      allow(described_class).to receive(:sync!).and_call_original

      result = described_class.route(POSITIVE_UTTERANCE)

      expect(described_class).to have_received(:sync!).once
      expect(described_class::Example.count).to be > 0
      expect(result[:tool]).to eq(TARGET_TOOL)
    end
  end
end
