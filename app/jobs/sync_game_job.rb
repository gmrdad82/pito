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

    # Run IGDB sync without the chat broadcast (conversation_id: nil).
    # GameIgdbSync handles the resyncing mutex + error posture.
    GameIgdbSync.perform_now(game_id)

    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    game.reload
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/sync game #{game.title}".strip
    )

    summary_text = Pito::Copy.render("pito.copy.sync.game_done", { title: game.title })

    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { "text" => summary_text }
    )

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncGameJob] failed for game=#{game_id}: #{e.class}: #{e.message}")
  end
end
