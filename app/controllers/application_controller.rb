class ApplicationController < ActionController::Base
  # Cookie-backed session auth. Anonymous-allowed actions (the login form,
  # OAuth pre-login entry points) declare themselves via `allow_anonymous`
  # at the class level.
  include Sessions::AuthConcern

  # UTC-storage / user-tz-render is the app-wide contract. All requests
  # render times in the owner's time zone (currently Etc/UTC, configurable
  # via AppSetting in the future).
  before_action :set_user_time_zone

  # Translate ActiveRecord::RecordNotFound into a clean JSON 404.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_conversation

  private

  def current_conversation
    if params[:uuid].present?
      Conversation.find_by!(uuid: params[:uuid])
    else
      Conversation.singleton
    end
  end

  def set_user_time_zone
    Time.zone = "Etc/UTC"
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end
end
