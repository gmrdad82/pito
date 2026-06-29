# frozen_string_literal: true

# Chat-initiated IGDB sync for a single game.
#
# Wraps `GameIgdbSync` (the existing nightly+resync job) and adds a
# Standard summary broadcast when `conversation_id` is present.
#
# When called from the chat executor via `perform_later`, it runs the full IGDB
# sync (SyncGame service) and, on success, broadcasts a plain-text summary to
# the conversation under a fresh "/sync game <title>" turn.
#
# Reuses: GameIgdbSync.perform_now(game_id, conversation_id: nil) — but we want
# our OWN summary copy rather than GameIgdbSync's detail+enhanced broadcast.
# So we call GameIgdbSync with NO conversation_id (data only), then broadcast
# our own one-liner summary message.
class SyncGameJob < ApplicationJob
  queue_as :default

  def perform(game_id, conversation_id: nil)
    game = ::Game.find_by(id: game_id)
    return unless game

    broadcaster = nil
    turn        = nil

    if conversation_id.present?
      conversation = ::Conversation.find_by(id: conversation_id)
      if conversation
        broadcaster = Pito::Stream::Broadcaster.new(conversation:)
        turn = conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: "/sync game #{game.title}".strip
        )
        broadcaster.emit_thinking(turn:, dictionary: :syncing)
      end
    end

    # Run IGDB sync without the chat broadcast (conversation_id: nil).
    # GameIgdbSync handles the resyncing mutex + error posture.
    GameIgdbSync.perform_now(game_id)

    return unless turn

    game.reload
    intro = Pito::Copy.render_html(
      "pito.copy.sync.intro",
      { subject: game.title },
      shimmer: [ :subject ]
    )
    broadcaster.emit(turn:, kind: :system, payload: { "body" => intro, "html" => true })
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncGameJob] failed for game=#{game_id}: #{e.class}: #{e.message}")
    if turn && broadcaster
      # Emit the :error event so the chat turn shows what went wrong, then
      # resolve any open thinking indicator and close the turn cleanly.
      broadcaster.emit(
        turn:,
        kind:    :error,
        payload: {
          text:   Pito::Copy.render("pito.copy.errors.dispatch_failed"),
          detail: e.message
        }
      )
      broadcaster.resolve_thinking(turn:)
      broadcaster.complete_turn(turn:)
    end
  end
end
