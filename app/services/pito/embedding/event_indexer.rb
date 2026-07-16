# frozen_string_literal: true

module Pito
  module Embedding
    # Conversation search (3.0.0) — embed a single scrollback event so the
    # owner can search past turns semantically. Digest-gated like
    # `Game::EmbeddingIndexer` / `Video::EmbeddingIndexer`, but the embed
    # call itself is the FORGIVING `Client#embed` contract, not the strict
    # `#embed_batch` those two use: they run on an explicit sync/reindex
    # action where a raised `EmbeddingNil` is a useful, retryable job
    # failure, but this runs on every ordinary chat turn as best-effort
    # background enrichment — a sidecar hiccup must never fail the turn
    # that produced the event, so a nil embedding is a silent no-write.
    #
    # Single-event only; batching (e.g. a backfill sweep over existing
    # events) is the caller's business, not this class's.
    class EventIndexer
      # Kinds carrying owner-searchable conversation content — the text an
      # operator would actually type into a search box later. Everything
      # else is UI mechanics, not conversation memory, and never embeds:
      # `error`/`thinking`/`confirmation`(`_follow_up`) are chrome around a
      # turn rather than the turn's content, and `theme_diff` is a cosmetic
      # event with no prose at all.
      EMBEDDABLE_KINDS = %w[
        echo system enhanced ai system_follow_up enhanced_follow_up
      ].freeze

      def self.call(event, force: false)
        new(event, force: force).call
      end

      def initialize(event, force: false)
        @event = event
        @force = force
      end

      def call
        return unless EMBEDDABLE_KINDS.include?(@event.kind)

        text = Pito::Mcp::EventText.call([ @event ]).to_s
        return if text.strip.blank?
        return if ENV["PITO_EMBEDDER_URL"].blank?

        # Salted with Pito::Embedding::Client::VECTOR_SPACE, not bare text
        # (3.0.1 correctness fix): the digest must identify the VECTOR SPACE
        # a stored embedding lives in, not just the source text. A text-only
        # digest can't detect a wire-level prompt change (e.g. the 3.0.0 ->
        # 3.0.1 PROMPT_PREFIX adoption) — the text is unchanged, so the
        # digest still matches, so the gate below would skip forever,
        # leaving a raw-space vector silently mismatched against prefixed
        # queries. See VECTOR_SPACE's doc comment for the full story.
        digest = Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + text)
        # Diff-gate: skip re-embedding when the projected text hasn't
        # changed (a follow-up stamp or fx re-render touching unrelated
        # payload keys shouldn't burn an embedder call) AND a vector is
        # already stored. The vector check matters: a matching digest with a
        # NULL `embedding` is exactly what a 2.x -> 3.0.0 column promotion
        # (or any other event that reached this gate before ever embedding
        # successfully) can leave behind — skipping on digest alone would
        # leave it permanently unembedded (3.0.1 P9-A). `force:` bypasses
        # the whole gate.
        return if !@force && digest == @event.embedded_digest && @event.embedding.present?

        embed_and_persist(text, digest)
      end

      private

      def embed_and_persist(text, digest)
        # Forgiving client path — deliberate contrast with
        # `Game::EmbeddingIndexer` / `Video::EmbeddingIndexer`'s strict
        # `embed_batch`: those two embed a handful of catalog rows on an
        # explicit sync/reindex action, so a raised `EmbeddingNil` is
        # a useful, visible job failure. This rides along on every ordinary
        # chat turn instead — the sidecar hiccuping must never fail the
        # turn that produced the event — so `#embed`'s nil-slot-on-any-
        # failure contract is exactly right here: a nil vector is silently
        # skipped, never raised.
        vector = Pito::Embedding::Client.new.embed([ text ]).first
        return if vector.nil?

        # `update_columns` skips validations + callbacks on purpose:
        # embedding an event must NOT rebroadcast it (same rationale as the
        # game/video indexers skipping their own after_save chains) — this
        # is a quiet background write, not a scrollback-visible mutation.
        # One statement (not two `update_column` calls) so a mid-write crash
        # can never leave a fresh vector paired with a stale digest.
        @event.update_columns(embedding: vector, embedded_digest: digest)
      end
    end
  end
end
