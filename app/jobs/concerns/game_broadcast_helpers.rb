# frozen_string_literal: true

# Shared broadcast helpers for jobs that emit the standard game detail
# (kind: :system) and enhanced (kind: :enhanced) messages into a conversation
# over ActionCable.
#
# Mixed into:
#   - GameImportJob  (emits both after the 5-step import flow)
#   - GameIgdbSync   (BUG B: emits both after a chat-initiated resync)
#
# All helpers are idempotent — guarded by event-kind existence checks so a
# retry or duplicate call does not duplicate events in the conversation.
module GameBroadcastHelpers
  # Find (or create) an open import turn for `title` in `conversation`.
  # "Open" = completed_at is nil. This allows a retry to re-enter the
  # same turn without duplicating it.
  #
  # @param conversation [Conversation]
  # @param title        [String]
  # @return [Turn]
  def import_turn(conversation, title)
    input_text = "/games import #{title}".strip
    conversation.turns
      .where(input_text: input_text, completed_at: nil)
      .order(:position)
      .last ||
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :slash,
        input_text: input_text
      )
  end

  # Emit the echo event if not already present on the turn.
  # The echo opens the `#turn_<id>` container in the scrollback.
  #
  # @param broadcaster [Pito::Stream::Broadcaster]
  # @param turn        [Turn]
  # @param title       [String]
  # @param conversation [Conversation]
  def emit_echo_once(broadcaster, turn:, title:, conversation:)
    return if turn.events.exists?(kind: "echo")

    echo_event = Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :echo,
      payload: { text: "/games import #{title}".strip, authenticated: true }
    )
    broadcaster.broadcast_event(echo_event)
  end

  # Emit the standard detail event (kind: :system) if not already present.
  # Idempotent: skips if a :system event already exists on the turn.
  #
  # @param broadcaster [Pito::Stream::Broadcaster]
  # @param turn        [Turn]
  # @param game        [::Game]
  # @param conversation [Conversation]
  def emit_detail_once(broadcaster, turn:, game:, conversation:)
    return if turn.events.exists?(kind: "system")

    detail_payload = Pito::MessageBuilder::Game::Detail.call(game, conversation: conversation)
    detail_event   = Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :system,
      payload: detail_payload
    )
    broadcaster.broadcast_event(detail_event)
  end

  # Emit the enhanced message event (kind: :enhanced) if not already present.
  # Idempotent: skips if an :enhanced event already exists on the turn.
  #
  # @param broadcaster [Pito::Stream::Broadcaster]
  # @param turn        [Turn]
  # @param game        [::Game]
  # @param conversation [Conversation]
  def emit_enhanced_once(broadcaster, turn:, game:, conversation:)
    return if turn.events.exists?(kind: "enhanced")

    enhanced_event = Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :enhanced,
      payload: Pito::MessageBuilder::Game::Enhanced.call(game)
    )
    broadcaster.broadcast_event(enhanced_event)
  end
end
