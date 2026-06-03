# frozen_string_literal: true

# Executes the confirmed or cancelled branch of a pending confirmation event.
#
# Extensible: the `command` field in the event payload determines which executor
# runs. Adding a new confirmation type requires only: (1) emitting a confirmation
# event with `command: "your_command"`, `confirmation_handle:`, and whatever
# data the executor needs; (2) adding a case in `execute_confirm`.
class ConfirmationDispatchJob < ApplicationJob
  queue_as :default

  def perform(event_id, action:)
    event        = Event.find(event_id)
    conversation = event.conversation
    payload      = event.payload.with_indifferent_access
    command      = payload[:command].to_s

    outcome_text = action.to_s == "confirm" ? execute_confirm(command, payload) : execute_cancel(command, payload)

    event.update!(
      kind:    :confirmation_follow_up,
      payload: payload.to_h.merge(
        "processing"   => false,
        "resolved"     => true,
        "outcome"      => action.to_s,
        "outcome_text" => outcome_text
      )
    )

    Pito::Stream::Broadcaster.new(conversation:).replace_event(event)
  rescue StandardError => e
    event = Event.find_by(id: event_id)
    return unless event

    event.update!(
      kind:    :confirmation_follow_up,
      payload: (event.payload || {}).merge(
        "processing"   => false,
        "resolved"     => true,
        "outcome"      => "error",
        "outcome_text" => I18n.t("pito.confirmation.errors.execution_failed")
      )
    )
    Pito::Stream::Broadcaster.new(conversation: event.conversation).replace_event(event)
    raise
  end

  private

  def execute_confirm(command, payload)
    case command
    when "disconnect" then confirm_disconnect(payload)
    else I18n.t("pito.confirmation.confirmed.default")
    end
  end

  def execute_cancel(command, payload)
    case command
    when "disconnect"
      channel = Channel.find_by(id: payload[:channel_id])
      handle  = channel&.handle&.presence || channel&.title.to_s
      I18n.t("pito.slash.disconnect.confirmation.cancelled", handle: handle.presence || "the channel")
    else
      I18n.t("pito.confirmation.cancelled.default")
    end
  end

  def confirm_disconnect(payload)
    channel = Channel.find_by(id: payload[:channel_id])
    return I18n.t("pito.slash.disconnect.errors.already_gone") if channel.nil?

    handle        = channel.handle.presence || channel.title.to_s
    video_count   = channel.videos.count
    connection_id = channel.youtube_connection_id

    ActiveRecord::Base.transaction do
      channel.destroy!
      if connection_id && !Channel.exists?(youtube_connection_id: connection_id)
        YoutubeConnection.find_by(id: connection_id)&.destroy
      end
    end

    I18n.t("pito.slash.disconnect.confirmation.confirmed", handle: handle, count: video_count)
  end
end
