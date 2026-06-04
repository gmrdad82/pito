# frozen_string_literal: true

# Handles toggle endpoints for install-wide AppSetting flags.
# All actions require authentication (no allow_anonymous).
class SettingsController < ApplicationController
  # POST /settings/expand_all
  # Body: { expand_all: true|false }
  # Flips AppSetting.expand_all to the requested value, then broadcasts
  # the updated #pito-settings element over the current conversation's
  # Turbo Stream so the change propagates to any live listeners.
  def toggle_expand_all
    new_value = ActiveModel::Type::Boolean.new.cast(params[:expand_all])
    AppSetting.expand_all = new_value

    # Broadcast the settings update over the current conversation stream so
    # any open cable connections receive the new data-expand-all attribute.
    uuid = params[:uuid].presence
    if uuid
      conversation = Conversation.find_by(uuid:)
      Pito::Stream::Broadcaster.new(conversation:).broadcast_settings_update if conversation
    end

    head :no_content
  end
end
