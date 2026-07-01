# frozen_string_literal: true

# Orchestrates the full 5-step IGDB import flow.
#
# Rework: the 5 steps run INSIDE the sidebar (not in the main chat).
# Each step is broadcast as a Turbo Stream `replace` targeting the
# `import-step-N` DOM elements that `pito--games-search` pre-renders when
# the user selects a game.  The sidebar stays open with all 5 steps marked
# done (Esc to close).
#
# TWO messages go to the main chat —
#   (a) an announce message (Pito::MessageBuilder::Game::ImportAnnounce, kind: :system)
#       after steps 1–2, with the verb "imported" or "re-synced".
#   (b) a done message (Pito::MessageBuilder::Game::ImportDone, kind: :enhanced)
#       after steps 3–5, followupable with reply_target "game_imported".
# Both land inside the job's Turn so they get the normal timestamp + follow-up chrome.
#
# ONE thinking indicator spans the whole import (19.1): emitted before step 1,
# resolved once after the done message. (The old per-phase importing/syncing pair
# left orphan thinking blocks — leftovers from when the flow emitted extra
# :enhanced messages.)
#
# Flow:
#   1. Find/create the open import turn.
#   2. Emit the import thinking indicator (:importing).
#   3. Sidebar step 1 shimmers; run SyncGame (IGDB main info + genres + companies + cover art).
#   4. Mark sidebar step 1 done; mark step 2 done (cover already fetched).
#   5. Emit :system announce to main chat (thinking stays live).
#   7. Shimmer step 3; run ScoreCalculator; mark step 3 done.
#   8. Shimmer step 4; run VoyageIndexer (digest-gated); mark step 4 done.
#   9. Shimmer step 5; call Pito::Recommendations; mark step 5 done.
#  10. Emit :enhanced done to main chat; resolve the thinking indicator.
#  11. Complete the turn.
#
# All 5 stages run inline (synchronous orchestration — no sub-job fan-out).
#
# Retry policy (BUG A fix):
#   Voyage transiently returning nil raises Pito::Error::VoyageEmbeddingNil.
#   Rather than swallowing the error (old behaviour, left games without embeddings),
#   we retry the WHOLE job up to 5 times with polynomial backoff.
#   On exhaustion, `degrade_after_voyage_exhaustion` emits the done message
#   (intro-only is acceptable) and completes the turn so it isn't left stuck open.
#
# Idempotency:
#   `perform` is re-entrant — a retry re-uses the existing open turn and skips
#   already-emitted events (system / enhanced) so they are never duplicated.
class GameImportJob < ApplicationJob
  include GameBroadcastHelpers

  queue_as :default

  # Retry up to 5 times on a transient Voyage nil-embedding failure.
  # On exhaustion the block degrades gracefully (emit done if needed, close turn).
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

    @title       = title
    @broadcaster = Pito::Stream::Broadcaster.new(conversation: @conversation)

    # Find or create the open import turn (idempotent on retry).
    turn = import_turn(@conversation, title)

    # Step 1 — Resolve/create Game + fetch IGDB main info (shimmer shown by JS).
    broadcast_step_pending(@broadcaster, step: 1)

    result  = Game::Igdb::Importer.call(igdb_id: igdb_id, title: title)
    @game   = result[:game]
    @action = result[:action]

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

    # Announce — :system "importing…" status message (steps 1–2 done). NO thinking
    # precedes it. Then a SINGLE thinking indicator spans the remaining work and
    # resolves when the :enhanced done message lands (19.1 — the old flow emitted
    # extra thinking blocks for the since-removed similar-games / recommended-
    # channels messages; only this one, resolving into `done`, remains).
    emit_announce_once(@broadcaster, turn: turn, game: @game.reload, conversation: @conversation)
    @broadcaster.emit_thinking(turn: turn, dictionary: :syncing)

    # Step 3 — Score
    broadcast_step_pending(@broadcaster, step: 3)
    @game.reload
    score = Pito::Game::ScoreCalculator.call(@game)
    @game.update_column(:score, score) if score != @game.score
    broadcast_step_done(@broadcaster, step: 3)

    # Step 4 — Voyage index (digest-gated; no-op if already fresh).
    broadcast_step_pending(@broadcaster, step: 4)
    # VoyageEmbeddingNil propagates to retry_on — not swallowed here.
    ::Game::VoyageIndexer.call(@game)
    broadcast_step_done(@broadcaster, step: 4)

    # Step 5 — Recommendations (dummy placeholder).
    broadcast_step_pending(@broadcaster, step: 5)
    Pito::Recommendations.call(@game)
    broadcast_step_done(@broadcaster, step: 5)

    # Done — :enhanced message after steps 3–5.
    emit_done_once(@broadcaster, turn: turn, game: @game, conversation: @conversation)
    @broadcaster.resolve_thinking(turn: turn)

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
    # Resolve any still-spinning thinking indicator so the error lands with
    # its thinking block resolved (no hung spinner).
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  end

  def handle_error(conversation, error)
    return unless conversation
    Rails.logger.error("[GameImportJob] #{error.class}: #{error.message}")
  rescue StandardError
    nil
  end

  # Emit the :system announce event if not already present on the turn.
  # Idempotent: skips if a :system event already exists on the turn.
  def emit_announce_once(broadcaster, turn:, game:, conversation:)
    return if turn.events.exists?(kind: :system)

    payload = Pito::MessageBuilder::Game::ImportAnnounce.call(
      game,
      action:       @action || :import,
      conversation: conversation
    )
    event = Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :system,
      payload: payload
    )
    broadcaster.broadcast_event(event)
  end

  # Emit the :enhanced done event if not already present on the turn.
  # Idempotent: skips if an :enhanced event already exists on the turn.
  def emit_done_once(broadcaster, turn:, game:, conversation:)
    return if turn.events.exists?(kind: :enhanced)

    payload = Pito::MessageBuilder::Game::ImportDone.call(game, conversation: conversation)
    event   = Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :enhanced,
      payload: payload
    )
    broadcaster.broadcast_event(event)
  end

  # Called by the retry_on exhaustion block (runs on the same job instance).
  # Instance vars @conversation, @broadcaster, @game, @title were set in
  # `perform` before the VoyageEmbeddingNil was raised, so they're available here.
  # Emits the done message in intro-only mode (empty embedding → no recs)
  # and completes the turn so it isn't left stuck open.
  def degrade_after_voyage_exhaustion
    return unless @conversation && @game

    turn = import_turn(@conversation, @title)

    emit_done_once(@broadcaster, turn: turn, game: @game, conversation: @conversation)
    @broadcaster.resolve_thinking(turn: turn)

    @broadcaster.complete_turn(turn: turn)
    Rails.logger.warn("[GameImportJob] Voyage embedding exhausted for game id=#{@game.id}; degrading to intro-only done message")
  rescue StandardError => e
    Rails.logger.warn("[GameImportJob] degrade_after_voyage_exhaustion failed: #{e.class}: #{e.message}")
  end
end
