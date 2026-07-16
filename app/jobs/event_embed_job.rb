# Conversation search (3.0.0) — embed every event of a just-completed turn so
# the owner can search past turns semantically. Enqueued once per turn from
# `Pito::Stream::Broadcaster#complete_turn`, the single choke point every
# dispatch path (jobs, the dispatch finalizer, the chat controller) routes
# through when it marks a turn done.
#
# Thin wrapper, same voice as `GameEmbedIndexJob`: look the row up, guard on
# a vanished record, hand off. Unlike that job, the hand-off is a blanket
# iteration over the turn's events rather than a single call — cheap and
# idempotent because `Pito::Embedding::EventIndexer.call` carries its own
# allowlist (kind), blank-text, digest, and `PITO_EMBEDDER_URL` guards, so
# re-running this job (or re-embedding a turn that had only one embeddable
# event) is a no-op past the first successful embed.
#
# Queue is `:search` — same lane as `GameEmbedIndexJob` / `SearchIndexJob`.
class EventEmbedJob < ApplicationJob
  queue_as :search

  # No retry_on, deliberately unlike `GameEmbedIndexJob`'s
  # `retry_on Pito::Error::EmbeddingNil`: that job embeds a catalog row
  # on an explicit sync/reindex action, where a raised nil embedding is a
  # useful, visible job failure worth retrying. `EventIndexer` embeds a
  # scrollback event on every ordinary chat turn instead — it's forgiving by
  # design (a nil vector is a silent no-write, never a raise) — so there's
  # nothing here to retry; a failed embed just self-heals on the next
  # reindex sweep over events (`pito:embeddings:reindex` already covers
  # events; see `Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS`).
  def perform(turn_id)
    turn = Turn.find_by(id: turn_id)
    return unless turn

    turn.events.find_each { |event| Pito::Embedding::EventIndexer.call(event) }
  end
end
