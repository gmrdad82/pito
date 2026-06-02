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
#   4. Stamp turn.completed_at and compute elapsed_seconds.
#   5. Broadcast each result Event (elapsed_seconds included in payload).
class ChatDispatchJob < ApplicationJob
  queue_as :default

  def perform(turn_id, channel:, period: nil, authenticated: true)
    turn         = Turn.find(turn_id)
    conversation = turn.conversation
    input        = turn.input_text
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    # Auth gating: only /authenticate works while unauthenticated (handled
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
    elsif turn.input_kind == "slash"
      Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
    else
      Pito::Chat::Dispatcher.call(input:, conversation:)
    end

    # Stamp completion before persisting result events so elapsed_seconds is
    # accurate when events are rendered.
    turn.update!(completed_at: Time.current)
    elapsed = turn.elapsed_seconds

    persist_and_broadcast(result, turn, conversation, broadcaster, elapsed)
    broadcaster.resolve_thinking(turn:, elapsed_seconds: elapsed)
  rescue StandardError => e
    # Surface the error as a visible event in the scrollback so the user isn't
    # left staring at a spinning Braille indicator (P25).
    turn = Turn.find_by(id: turn_id)
    return unless turn

    conversation = turn.conversation
    turn.update!(completed_at: Time.current) unless turn.completed_at?
    elapsed = turn.elapsed_seconds
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(
      turn:,
      kind: "error",
      payload: {
        text:             I18n.t("pito.errors.dispatch_failed").sample,
        detail:           e.message,
        elapsed_seconds:  elapsed
      }
    )
    broadcaster.resolve_thinking(turn:, elapsed_seconds: elapsed)
    raise # re-raise so SolidQueue marks the job failed and can retry
  end

  private

  def persist_and_broadcast(result, turn, conversation, broadcaster, elapsed)
    events_to_emit = result_events(result, elapsed)
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
  # elapsed_seconds is injected into every result payload so P25 (Braille
  # indicator) can display "Executed for Ns" without a separate broadcast.
  def result_events(result, elapsed)
    base = { elapsed_seconds: elapsed }

    case result
    when Pito::Slash::Result::Ok, Pito::Chat::Result::Ok, Pito::Chat::Result::Refine
      inject_segment_styles(result.events).map { |e| { kind: e[:kind], payload: e[:payload].merge(base) } }

    when Pito::Slash::Result::Error, Pito::Chat::Result::Error
      # If message_key looks like already-translated text (e.g. a sampled
      # mandatory), pass it as text: so ErrorComponent renders it directly.
      error_payload = if result.message_key.to_s.start_with?("pito.")
        { message_key: result.message_key, message_args: result.message_args }
      else
        { text: result.message_key }
      end
      [ { kind: "error", payload: error_payload.merge(base) } ]

    when Pito::Slash::Result::NeedsConfirmation
      [ { kind: "confirmation_prompt",
          payload: { prompt_key:    result.prompt_key,
                     prompt_args:   result.prompt_args,
                     command_text:  result.command_text }.merge(base) } ]

    else
      []
    end
  end

  # Inject `segment_style` into assistant_text events based on position:
  #   first  → "plain" (no accent / no background)
  #   2nd+   → "subsequent" (blue accent / no background)
  #   follow_up flag → "follow_up" (blue accent / surface background)
  def inject_segment_styles(events)
    assistant_indices = events.each_index.select { |i| events[i][:kind].to_s == "assistant_text" }

    events.each_with_index.map do |e, idx|
      next e unless e[:kind].to_s == "assistant_text"

      style = if e[:payload][:follow_up] == true || e[:payload]["follow_up"] == true
        "follow_up"
      elsif assistant_indices.first == idx
        "plain"
      else
        "subsequent"
      end

      { kind: e[:kind], payload: e[:payload].merge(segment_style: style) }
    end
  end
end
