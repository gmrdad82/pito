# frozen_string_literal: true

# Orchestrates the full 5-step IGDB import flow.
#
# T16.8 rework: the 5 steps run INSIDE the sidebar (not in the main chat).
# Each step is broadcast as a Turbo Stream `replace` targeting the
# `import-step-N` DOM elements that `pito--games-search` pre-renders when
# the user selects a game.  The sidebar stays open with all 5 steps marked
# done (Esc to close).
#
# T16.9: only TWO messages go to the main chat —
#   (a) the standard detail message (Pito::Game::DetailMessage) after steps 1–3.
#   (b) the enhanced message (Pito::Copy body + make_followupable!) after steps 4–5.
# Both land inside the job's Turn so they get the normal timestamp + follow-up chrome.
#
# Flow:
#   1. Resolve/create the Game record via Game::Igdb::Importer.
#   2. Sidebar step 1 shimmers; run SyncGame (IGDB main info + genres + companies + cover art).
#   3. Mark sidebar step 1 done; shimmer step 2; mark step 2 done (cover already fetched).
#   4. Shimmer step 3; run ScoreCalculator; mark step 3 done.
#   5. Stream the standard P9 detail chat message (after step 3).
#   6. Shimmer step 4; run VoyageIndexer (digest-gated); mark step 4 done.
#   7. Shimmer step 5; call dummy Pito::Recommendations; mark step 5 done.
#   8. Stream the enhanced chat message (after step 5).
#   9. Complete the turn.
#
# All 5 stages run inline (synchronous orchestration — no sub-job fan-out).
#
# Retry policy (BUG A fix):
#   Voyage transiently returning nil raises Pito::Error::VoyageEmbeddingNil.
#   Rather than swallowing the error (old behaviour, left games without embeddings),
#   we retry the WHOLE job up to 5 times with polynomial backoff.
#   On exhaustion, `degrade_after_voyage_exhaustion` emits the enhanced message
#   (intro-only is acceptable) and completes the turn so it isn't left stuck open.
#
# Idempotency:
#   `perform` is re-entrant — a retry re-uses the existing open turn and skips
#   already-emitted events (echo / detail / enhanced) so they are never duplicated.
class GameImportJob < ApplicationJob
  include GameBroadcastHelpers

  queue_as :default

  # Retry up to 5 times on a transient Voyage nil-embedding failure.
  # On exhaustion the block degrades gracefully (emit enhanced if needed, close turn).
  retry_on Pito::Error::VoyageEmbeddingNil,
           wait: :polynomially_longer,
           attempts: 5 do |job, _error|
    job.send(:degrade_after_voyage_exhaustion)
  end

  STEP_COPY_KEYS = [
    nil,                                 # 1-indexed; index 0 unused
    "pito.copy.games.import.step1",
    "pito.copy.games.import.step2",
    "pito.copy.games.import.step3",
    "pito.copy.games.import.step4",
    "pito.copy.games.import.step5"
  ].freeze

  def perform(igdb_id:, title:, conversation_id:)
    @conversation = Conversation.find_by(id: conversation_id)
    return unless @conversation

    @title        = title
    @broadcaster  = Pito::Stream::Broadcaster.new(conversation: @conversation)

    # Find or create the open import turn (idempotent on retry).
    turn = import_turn(@conversation, title)

    # Echo the import invocation so the user sees what triggered the flow.
    emit_echo_once(@broadcaster, turn: turn, title: title, conversation: @conversation)

    # Step 1 — Resolve/create Game + fetch IGDB main info (shimmer shown by JS).
    broadcast_step_pending(@broadcaster, step: 1)

    result = Game::Igdb::Importer.call(igdb_id: igdb_id, title: title)
    @game  = result[:game]

    # Run SyncGame synchronously so we have the full payload for step 2+.
    @game.update_column(:resyncing, true)
    begin
      Game::Igdb::SyncGame.new.call(@game)
    rescue Game::Igdb::Client::ValidationError => e
      emit_error(@broadcaster, turn: turn, conversation: @conversation, message: e.message)
      return
    ensure
      Game.where(id: @game.id).update_all(resyncing: false)
    end
    @game.reload

    broadcast_step_done(@broadcaster, step: 1)

    # Step 2 — Cover art (already fetched by SyncGame above). The client already
    # pre-renders this row as a shimmer, so we ONLY broadcast `done` — emitting a
    # back-to-back pending+done raced over the cable and left the shimmer stuck.
    broadcast_step_done(@broadcaster, step: 2)

    # Step 3 — Score
    broadcast_step_pending(@broadcaster, step: 3)
    @game.reload
    score = Pito::Game::ScoreCalculator.call(@game)
    @game.update_column(:score, score) if score != @game.score
    broadcast_step_done(@broadcaster, step: 3)

    # After Step 3 — stream the standard P9 detail message to main chat (T16.9).
    emit_detail_once(@broadcaster, turn: turn, game: @game.reload, conversation: @conversation)

    # Step 4 — Voyage index (digest-gated; no-op if already fresh).
    broadcast_step_pending(@broadcaster, step: 4)
    # VoyageEmbeddingNil propagates to retry_on — not swallowed here.
    ::Game::VoyageIndexer.call(@game)
    broadcast_step_done(@broadcaster, step: 4)

    # Step 5 — Recommendations (dummy placeholder; real logic in P13).
    broadcast_step_pending(@broadcaster, step: 5)
    Pito::Recommendations.call(@game)
    broadcast_step_done(@broadcaster, step: 5)

    # After Step 5 — stream the enhanced chat message to main chat (T16.9).
    # kind: :enhanced → renders via Pito::Event::EnhancedComponent (the pito
    # brand-blue border chrome). NOT follow-up-able: only the standard detail
    # message carries a #handle. Shared builder with `show game <ref>`.
    emit_enhanced_once(@broadcaster, turn: turn, game: @game, conversation: @conversation)

    @broadcaster.complete_turn(turn: turn)
  rescue Pito::Error::VoyageEmbeddingNil
    # Let retry_on handle this — do NOT log as a hard job error on each attempt.
    raise
  rescue StandardError => e
    handle_error(@conversation, e)
    raise
  end

  private

  # Broadcast a "pending" step indicator to the sidebar (shimmer dot, dim label).
  # The JS has already rendered all 5 rows as shimmer; this is a no-op for the
  # first step but ensures later steps also show the shimmer while running.
  def broadcast_step_pending(broadcaster, step:)
    label = Pito::Copy.render(STEP_COPY_KEYS[step])
    broadcaster.broadcast_import_step(step: step, label: label, done: false)
  end

  # Mark a sidebar step as done (checkmark, full-brightness label).
  def broadcast_step_done(broadcaster, step:)
    label = Pito::Copy.render(STEP_COPY_KEYS[step])
    broadcaster.broadcast_import_step(step: step, label: label, done: true)
  end

  def emit_error(broadcaster, turn:, conversation:, message:)
    event = Event.create_with_position!(
      conversation:, turn:, kind: :error,
      payload: {
        text:   Pito::Copy.render("pito.copy.errors.dispatch_failed"),
        detail: message
      }
    )
    broadcaster.broadcast_event(event)
    broadcaster.complete_turn(turn:)
  end

  def handle_error(conversation, error)
    return unless conversation
    Rails.logger.error("[GameImportJob] #{error.class}: #{error.message}")
  rescue StandardError
    nil
  end

  # Called by the retry_on exhaustion block (runs on the same job instance).
  # Instance vars @conversation, @broadcaster, @game, @title were set in
  # `perform` before the VoyageEmbeddingNil was raised, so they're available here.
  # Emits the enhanced message in intro-only mode (empty embedding → no recs)
  # and completes the turn so it isn't left stuck open.
  def degrade_after_voyage_exhaustion
    return unless @conversation && @game

    turn = import_turn(@conversation, @title)

    # Emit enhanced-once (intro-only is acceptable without embeddings).
    emit_enhanced_once(@broadcaster, turn: turn, game: @game, conversation: @conversation)

    @broadcaster.complete_turn(turn: turn)
    Rails.logger.warn("[GameImportJob] Voyage embedding exhausted for game id=#{@game.id}; degrading to intro-only enhanced message")
  rescue StandardError => e
    Rails.logger.warn("[GameImportJob] degrade_after_voyage_exhaustion failed: #{e.class}: #{e.message}")
  end
end
