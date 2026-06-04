# frozen_string_literal: true

# Handles toggle endpoints for install-wide AppSetting flags.
# All actions require authentication (no allow_anonymous).
class SettingsController < ApplicationController
  # POST /settings/expand_all
  # Body: { expand_all: true|false }
  # Flips AppSetting.expand_all to the requested value, then broadcasts
  # the updated #pito-settings element to pito:global so every open tab
  # (including the current one) receives the new data-expand-all attribute.
  # Newly-arrived cable segments call expandAllEnabled() on connect() and
  # therefore inherit the correct value without a reload.
  def toggle_expand_all
    new_value = ActiveModel::Type::Boolean.new.cast(params[:expand_all])
    AppSetting.expand_all = new_value

    # P55 — broadcast to pito:global so all open tabs/instances update
    # #pito-settings immediately. The current tab's expand_controller
    # already flips existing segments optimistically; the Turbo replace
    # ensures expandAllEnabled() returns the correct value for future
    # cable-delivered segments.
    Pito::Stream::Broadcaster.broadcast_global_settings_update

    head :no_content
  end
end
