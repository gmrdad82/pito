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
      row = described_class::Example.find_by!(
        digest: Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + TARGET_PHRASE)
      )
      expect(row.embedding).to eq(target_vector)

      described_class.sync!

      expect(row.reload.embedding).to eq(target_vector)
    end

    # ── Digest salt (3.0.1 correctness fix) ────────────────────────────────
    # `nl_examples.digest` must identify the VECTOR SPACE a cached row's
    # embedding lives in, not just its phrase text — see
    # Pito::Embedding::Client::VECTOR_SPACE's doc comment. A text-only
    # digest can't detect a wire-level prompt change: the phrase is
    # unchanged, so the digest would still match, so a raw-space row from
    # before the prompt changed would survive `sync!` untouched forever,
    # silently mismatched against prefixed `.route` queries.
    it "salts every materialized row's digest with Pito::Embedding::Client::VECTOR_SPACE" do
      described_class.sync!

      row = described_class::Example.find_by!(phrase: TARGET_PHRASE)
      expect(row.digest).to eq(Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + TARGET_PHRASE))
      expect(row.digest).not_to eq(Digest::SHA256.hexdigest(TARGET_PHRASE))
    end

    it "prunes a row whose digest was computed under a different VECTOR_SPACE and re-creates it fresh" do
      described_class.sync!
      stale_digest = Digest::SHA256.hexdigest("some-other-vector-space" + TARGET_PHRASE)
      described_class::Example.where(phrase: TARGET_PHRASE).delete_all
      described_class::Example.create!(tool: "list", phrase: TARGET_PHRASE, digest: stale_digest)

      described_class.sync!

      expect(described_class::Example.where(digest: stale_digest)).not_to exist
      fresh_row = described_class::Example.find_by!(phrase: TARGET_PHRASE)
      expect(fresh_row.digest).to eq(Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + TARGET_PHRASE))
      # embed_pending! ran in the same sync! call, so the fresh row self-heals
      # straight to an embedded vector rather than sitting nil until the next sweep.
      expect(fresh_row.embedding).to eq(target_vector)
    end

    # 3.0.1 P11 — rake pito:nl:sync / NightlyReindexJob print these counts.
    describe "return value (upserted/pruned/embedded counts)" do
      it "reports the full corpus size as upserted and every row as embedded on a first sync" do
        result = described_class.sync!

        expect(result[:upserted]).to eq(expected_corpus_phrases.uniq.size)
        expect(result[:pruned]).to eq(0)
        expect(result[:embedded]).to eq(expected_corpus_phrases.uniq.size)
      end

      it "reports zero embedded (nothing pending) on a stable re-sync, upserted unchanged" do
        described_class.sync!
        result = described_class.sync!

        expect(result[:upserted]).to eq(expected_corpus_phrases.uniq.size)
        expect(result[:embedded]).to eq(0)
      end

      it "reports the real pruned-row count for a stray digest no longer in the corpus" do
        described_class.sync!
        described_class::Example.create!(
          tool: "list", phrase: "a stray fixture phrase absent from tools.yml",
          digest: Digest::SHA256.hexdigest("a stray fixture phrase absent from tools.yml")
        )

        expect(described_class.sync!.fetch(:pruned)).to eq(1)
      end
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

    it "snaps a first-word typo of a known tool onto its canonical form before matching" do
      allow(client).to receive(:embed) { |texts| texts.map { |text| vector_for(text) } }
      described_class.route("lisst me the clips")

      expect(client).to have_received(:embed).with([ "list me the vids" ])
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

  # ── First-word typo-snap (3.0.1 P11) ─────────────────────────────────────────
  # `.normalize` recovers a genuine, unambiguous typo of the FIRST word (the
  # word that would have been the literal tool/alias) BEFORE the synonym pass
  # runs and BEFORE the (now-corrected) text is embedded. Deliberately
  # length-graduated and restricted to chat-branch tools — see the method's
  # own comment for the full rationale: a flat Levenshtein<=2 against the
  # WHOLE tools+aliases vocabulary was measured to mis-correct 20+ real
  # phrases already live in this corpus/nl.exemplars/nl_calibration.yml
  # ("how" -> "show", "which" -> "with", "make"/"gimme" -> "game", "pull"/
  # "push" -> "pub") — this narrower version fixes the plan's own named
  # cases with none of that collateral damage.
  describe ".normalize (first-word typo-snap)" do
    it "snaps a distance-1 typo of a known tool onto its canonical form" do
      expect(described_class.normalize("impory game forza horizon 6")).to eq("import game forza horizon 6")
      expect(described_class.normalize("seach games like nioh")).to eq("search games like nioh")
    end

    it "still runs the synonym pass over the whole (now-corrected) word list" do
      expect(described_class.normalize("seach my clips for tekken")).to eq("search my vids for tekken")
    end

    it "leaves an already-known first word untouched" do
      expect(described_class.normalize("list me the vids")).to eq("list me the vids")
    end

    it "leaves a short first word untouched even when it resembles a tool (regression guard)" do
      # "how" sits 1 edit from "show" — exactly the kind of short-word
      # collision FIRST_WORD_TYPO_MIN_LENGTH exists to avoid; "how is X
      # performing?" is one of the analyze tool's own nl_examples shapes.
      expect(described_class.normalize("how is my channel doing")).to eq("how is my channel doing")
    end

    it "leaves a first word untouched when no known token sits within the length-graduated distance" do
      expect(described_class.normalize("throw away game 9")).to eq("throw away game 9")
    end

    it "leaves a first word untouched when it is ambiguous between two+ candidates" do
      # "brekdown" sits 2 edits from BOTH "breakdown" and "breakdowns" (the
      # breakdowns tool's own alias pair) — an ambiguous match never snaps,
      # even though both candidates happen to name the same tool.
      expect(described_class.normalize("brekdown game 2")).to eq("brekdown game 2")
    end
  end

  # ── Decision log (P8, 3.0.1) ─────────────────────────────────────────────────
  # Before this, `.route` logged nothing at all — an utterance that scored,
  # say, 0.6 left no trail explaining why chat silently dropped it. One line
  # per call that reaches a real score (the reported thresholds come straight
  # from tools.yml's `nl.thresholds` block: auto_run: 0.90, suggest: 0.75).
  describe "decision log" do
    before { described_class.sync! }

    it "logs score/tool/nearest/branch/utterance_len but never the raw utterance" do
      expect(Rails.logger).to receive(:info) do |message|
        expect(message).to include("[Pito::Nl::Router]")
        expect(message).to include("tool=#{TARGET_TOOL}")
        expect(message).to include(%(nearest="#{TARGET_PHRASE}"))
        expect(message).to include("branch=suggest")
        expect(message).to include("utterance_len=#{POSITIVE_UTTERANCE.length}")
        expect(message).not_to include(POSITIVE_UTTERANCE)
      end

      described_class.route(POSITIVE_UTTERANCE)
    end

    it "logs branch=nil when confidence sits below the suggest floor" do
      expect(Rails.logger).to receive(:info).with(a_string_including("branch=nil"))
      described_class.route(NEGATIVE_UTTERANCE)
    end

    it "logs branch=auto_run-eligible when confidence clears the auto_run floor" do
      expect(Rails.logger).to receive(:info).with(a_string_including("branch=auto_run-eligible"))
      described_class.route(TARGET_PHRASE) # exact match against its own corpus row -> confidence 1.0
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
