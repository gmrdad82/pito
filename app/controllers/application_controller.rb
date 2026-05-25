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

  # Auth errors from API namespace.
  rescue_from Api::Unauthorized, with: :render_api_unauthorized
  rescue_from Api::Forbidden,    with: :render_api_forbidden

  private

  def set_user_time_zone
    Time.zone = "Etc/UTC"
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_api_unauthorized(error)
    response.headers["WWW-Authenticate"] = Api::TokenAuthenticator.www_authenticate_header
    render json: { error: error.reason }, status: :unauthorized
  end

  def render_api_forbidden(error)
    render json: {
      error: "insufficient_scope",
      required: error.required_scope
    }, status: :forbidden
  end
end
