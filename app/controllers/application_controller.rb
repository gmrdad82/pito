class ApplicationController < ActionController::Base
  # Cookie-backed session auth. Anonymous-allowed actions (the login form,
  # OAuth pre-login entry points) declare themselves via `allow_anonymous`
  # at the class level.
  include Sessions::AuthConcern

  # UTC-storage / user-tz-render is the app-wide contract. All requests
  # render times in the owner's time zone (currently Etc/UTC, configurable
  # via AppSetting in the future).
  before_action :set_user_time_zone

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
    # Defensive: authenticate_session! may not have run if this is called
    # from a middleware-level error path (before before_actions fire).
    # Read the cookie directly so the not_found page reflects auth state.
    if Current.session.nil?
      data = Pito::Auth::SessionCookie.new(request).read
      Current.session = data if data
    end

    respond_to do |format|
      format.html do
        render(
          Pito::StartScreen::Component.new(
            repo_url:          ENV.fetch("PITO_REPO_URL", "https://github.com/gmrdad82/pito"),
            license_url:       ENV.fetch("PITO_LICENSE_URL", "https://www.gnu.org/licenses/agpl-3.0.html"),
            tips_key:          "pito.not_found.messages",
            badge_text:        "404",
            badge_class:       "font-bold text-red",
            exclamation_class: "text-red"
          ),
          status: :not_found
        )
      end
      format.any { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
