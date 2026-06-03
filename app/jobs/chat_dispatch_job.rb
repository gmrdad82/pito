# frozen_string_literal: true

# Async half of the chat dispatch pipeline (P23).
#
# The controller handles the synchronous front-end of every non-auth command
# (authenticated or not):
#   1. Resolve/create the conversation + turn (started_at auto-stamped).
#   2. Persist the echo Event.
#   3. Broadcast the echo.
#   4. Enqueue this job (with the `authenticated` flag).
#   5. Return 204 immediately.
#
# This job handles the rest:
#   1. Apply auth gating — an unauthenticated session is refused here.
#   2. Otherwise dispatch to the correct handler (slash or chat).
#   3. Persist each result Event first (so a page refresh mid-job shows the echo).
#   4. Resolve the thinking indicator (elapsed computed from its own started_at).
#   5. Complete the turn (broadcasts pito:done — dots hide).
class ChatDispatchJob < ApplicationJob
  queue_as :default

  def perform(turn_id, channel: nil, period: nil, authenticated: true)
    turn         = Turn.find(turn_id)
    conversation = turn.conversation
    input        = turn.input_text
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    # Auth gating: only /login works while unauthenticated (handled
    # synchronously in the controller). Every other command from an
    # unauthenticated session is refused here with the auth-required error.
    result = if !authenticated && !help_command?(input)
      # /help works unauthenticated (but shows restricted output). Everything else
      # is blocked. text: passes the already-resolved string to ErrorComponent.
      Pito::Chat::Result::Error.new(
        message_key: I18n.t("pito.auth.mandatories").sample,
        message_args: {}
        # NOTE: message_key here is already-translated text — ErrorComponent
        # handles this via the text: fallback path.
      )
    elsif turn.slash?
      Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
    else
      Pito::Chat::Dispatcher.call(input:, conversation:)
    end

    persist_and_broadcast(result, turn, conversation, broadcaster)
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    # Surface the error as a visible event in the scrollback so the user isn't
    # left staring at a spinning Braille indicator (P25).
    turn = Turn.find_by(id: turn_id)
    return unless turn

    conversation = turn.conversation
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(
      turn:,
      kind: :error,
      payload: {
        text:   I18n.t("pito.errors.dispatch_failed").sample,
        detail: e.message
      }
    )
    broadcaster.resolve_thinking(turn:)
    broadcaster.complete_turn(turn:)
    raise # re-raise so SolidQueue marks the job failed and can retry
  end

  private

  def persist_and_broadcast(result, turn, conversation, broadcaster)
    events_to_emit = result_events(result)
    events_to_emit.each do |attrs|
      event = Event.create_with_position!(
        conversation:,
        turn:,
        kind:    attrs[:kind],
        payload: attrs[:payload]
      )
      broadcaster.broadcast_event(event)
    end
  end

  def help_command?(input)
    input.strip.match?(%r{\A/help(\s|\z)}i)
  end

  # Translate a dispatcher Result into an array of { kind:, payload: } hashes.
  def result_events(result)
    case result
    when Pito::Slash::Result::Ok, Pito::Chat::Result::Ok, Pito::Chat::Result::Refine
      assign_canonical_kinds(result.events).map { |e| { kind: e[:kind], payload: e[:payload] } }

    when Pito::Slash::Result::Error, Pito::Chat::Result::Error
      # If message_key looks like already-translated text (e.g. a sampled
      # mandatory), pass it as text: so ErrorComponent renders it directly.
      error_payload = if result.message_key.to_s.start_with?("pito.")
        { message_key: result.message_key, message_args: result.message_args }
      else
        { text: result.message_key }
      end
      [ { kind: :error, payload: error_payload } ]

    else
      []
    end
  end

  # Assign canonical kinds to events that handlers emit as :system.
  # First system event → :system, subsequent → :enhanced.
  # follow_up: true flag → :system_follow_up / :enhanced_follow_up.
  def assign_canonical_kinds(events)
    system_indices = events.each_index.select { |i| events[i][:kind].to_s == "system" }

    events.each_with_index.map do |e, idx|
      next e unless e[:kind].to_s == "system"

      follow_up = e.dig(:payload, :follow_up) == true || e.dig(:payload, "follow_up") == true
      first     = system_indices.first == idx

      new_kind = if follow_up
        first ? :system_follow_up : :enhanced_follow_up
      else
        first ? :system : :enhanced
      end

      { kind: new_kind, payload: e[:payload] }
    end
  end
end
