# frozen_string_literal: true

# Async half of the chat dispatch pipeline.
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
  # Dedicated lane (config/queue.yml): command dispatch stays snappy no
  # matter what the general workers are grinding through.
  queue_as :dispatch

  def perform(turn_id, channel: nil, period: nil, authenticated: true, viewport_width: nil)
    turn         = Turn.find(turn_id)
    conversation = turn.conversation
    input        = turn.input_text
    finalizer    = Pito::Dispatch::Finalizer.new(conversation:)

    # Auth gating: only /login works while unauthenticated (handled
    # synchronously in the controller). Every other command from an
    # unauthenticated session is refused here with the auth-required error.
    result = if !authenticated && !help_command?(input)
      # /help works unauthenticated (but shows restricted output). Everything else
      # is blocked. text: passes the already-resolved string to ErrorComponent.
      Pito::Chat::Result::Error.new(
        message_key: Pito::Copy.render("pito.copy.auth.mandatories"),
        message_args: {}
        # NOTE: message_key here is already-translated text — ErrorComponent
        # handles this via the text: fallback path.
      )
    elsif turn.slash?
      Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
    elsif turn.hashtag?
      Pito::Hashtag::Dispatcher.call(input:, conversation:)
    else
      Pito::Dispatch::Router.call(input:, conversation:, channel:, period:, viewport_width:)
    end

    # The shared finalizer canonicalises kinds, persists + broadcasts each event,
    # then runs the analytics-fill gate (defer to AnalyticsFillJob, else resolve
    # the thinking indicator + complete the turn).
    finalizer.append_and_complete(events: Pito::Dispatch::Finalizer.result_events(result), turn:)

    # Compute + persist + broadcast the new showcase set (rule-based; no Voyage).
    # Runs after the turn is fully settled so the builder sees its completed events.
    suggestions = Pito::Showcase::Builder.call(conversation:)
    turn.update!(suggestions:)
    Pito::Stream::Broadcaster.new(conversation:).broadcast_showcase(suggestions:)
    Pito::Stream::Broadcaster.new(conversation:).broadcast_context_meter
  rescue StandardError => e
    # Surface the error as a visible event in the scrollback so the user isn't
    # left staring at a spinning Braille indicator.
    turn = Turn.find_by(id: turn_id)
    return unless turn

    Pito::Dispatch::Finalizer.new(conversation: turn.conversation).surface_error(turn:, detail: e.message)
    raise # re-raise so SolidQueue marks the job failed and can retry
  end

  private

  def help_command?(input)
    input.strip.match?(%r{\A/help(\s|\z)}i)
  end
end
