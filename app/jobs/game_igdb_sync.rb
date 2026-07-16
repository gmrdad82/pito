#
# Single argument `game_id`. On `Game::Igdb::Client::RateLimited` /
# `ServerError` / network errors, with
# exponential backoff (5 attempts). On `ValidationError` (game ID
# does not exist on IGDB) the local row is stamped with
# `last_sync_error` inside `Game::Igdb::SyncGame` and the job swallows
# the raise, not retrying.
#
# `games.resyncing` mutex flag.
# The job flips `resyncing` true at start (skips when already in
# flight, so duplicate enqueues are no-ops) and back to false in
# an `ensure` block so a crash inside `SyncGame` still releases
# the lock.
#
# Two-layer lock, mirroring `ReindexAllJob`'s pattern:
#
#   Layer 1 — DB mutex (`games.resyncing` Boolean). Set at start,
#             cleared in `ensure`. The controller consults the same
#             flag to short-circuit duplicate enqueues from the
#             breadcrumb [sync] click.
#
# UI feedback while a resync is in flight is handled entirely on
# `/games/:id` by the page-level `auto-refresh` controller (reloads
# every ~5 s while `@game.resyncing?` is true). The dedicated sync
# pane / banner and the `_sync_status` partial were removed —
# breadcrumb [sync] (muted-while-syncing) is the only
# control surface.
#
# Bundle cover-art fan-out removed with bundles.
#
# Optional `conversation_id:` keyword.
# When set (chat-initiated resync via Pito::Confirmation::Executor),
# after a successful sync + Voyage reindex the job broadcasts the
# updated standard detail + enhanced messages to that conversation
# under a fresh "/games resync <title>" slash turn.
# When nil (page-path resync via nightly job, console, or missing
# controller), behaviour is unchanged — no chat events are created.
class GameIgdbSync < ApplicationJob
  include GameBroadcastHelpers

  queue_as :default

  # `prefetched:` — bulk-fetched `{ game_json:, ttb_json: }`
  # passed through to SyncGame so batch callers (the nightly refresh) skip the
  # two per-game IGDB requests. perform_now callers only (in-memory payloads).
  def perform(game_id, conversation_id: nil, prefetched: nil)
    game = Game.find_by(id: game_id)
    return unless game

    # Controller-owned mutex flip. `GamesController#resync`
    # stamps `resyncing = true` SYNCHRONOUSLY before enqueuing the job
    # so the post-POST redirect renders the muted breadcrumb + auto-
    # refresh polling immediately (no race condition).
    # `update_column` skips validations / callbacks so this is safe to
    # call when the controller already set the flag (idempotent no-op).
    # The legacy `return if game.resyncing?` early-bail was retired in
    # lockstep — the controller now owns the gate (it short-circuits
    # duplicate user clicks with the "already resyncing." flash), and
    # console / rake callers that bypass the controller still get a
    # full sync because the job unconditionally flips the flag and runs.
    game.update_column(:resyncing, true)
    success = false
    begin
      Game::Igdb::SyncGame.new.call(game, prefetched:)
      success = true
    rescue Game::Igdb::Client::RateLimited => e
      sleep(e.retry_after.to_i.clamp(1, 60))
      raise
    rescue Game::Igdb::Client::ValidationError
      # Local row already stamped with last_sync_error inside SyncGame.
      # No re-raise — non-retryable.
      nil
    ensure
      # Re-load to clear the flag even if the inner update! mutated
      # other columns; `update_column` works on the persisted record
      # regardless of the in-memory state.
      Game.where(id: game.id).update_all(resyncing: false)
    end

    # Chat-path broadcast — only when a conversation_id was supplied and the
    # sync succeeded (ValidationError sets success=false and skips this block).
    return unless success && conversation_id.present?

    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    game.reload

    # Reindex so recommendations are fresh before the enhanced message.
    begin
      ::Game::EmbeddingIndexer.call(game)
    rescue Pito::Error::EmbeddingNil => e
      Rails.logger.warn("[GameIgdbSync] Embedding failed after resync for game id=#{game.id}: #{e.message}")
      # Continue — enhanced message will render intro-only (no recs). Acceptable.
    end

    broadcaster = Pito::Stream::Broadcaster.new(conversation: conversation)
    title = game.title

    # Create a fresh slash turn for this resync broadcast.
    turn = create_resync_turn(conversation, title)

    emit_echo_once(broadcaster, turn: turn, title: title, conversation: conversation)
    emit_detail_once(broadcaster, turn: turn, game: game.reload, conversation: conversation)
    emit_enhanced_once(broadcaster, turn: turn, game: game, conversation: conversation)

    broadcaster.complete_turn(turn: turn)
  end

  private

  # Create a new (always fresh) slash turn for a chat-initiated resync.
  # Unlike import_turn (which is idempotent/retryable), resync turns are
  # always new — there is no retry path that needs to re-enter the same turn.
  def create_resync_turn(conversation, title)
    conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/games resync #{title}".strip
    )
  end
end
