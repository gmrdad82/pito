class ApplicationController < ActionController::Base
  # Cookie-backed session auth. Anonymous-allowed actions (the login form,
  # OAuth pre-login entry points) declare themselves via `allow_anonymous`
  # at the class level.
  include Sessions::AuthConcern

  # UTC-storage / user-tz-render is the app-wide contract. All requests
  # render times in the owner's configured time zone (AppSetting.timezone,
  # default UTC). ActiveRecord keeps storing UTC internally.
  before_action :set_user_time_zone

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_conversation

  before_action :set_channels, if: -> { request.format.html? }

  private

  def set_channels
    @channels = Channel.order(:handle).compact.map(&:at_handle)
  end

  def current_conversation
    if params[:uuid].present?
      Conversation.find_by!(uuid: params[:uuid])
    else
      Conversation.singleton
    end
  end

  def set_user_time_zone
    Time.zone = AppSetting.timezone
  rescue StandardError
    # Never let a missing/unreadable setting break the request — fall back to UTC.
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
            tips_key:          "pito.copy.not_found",
            badge_text:        "404",
            badge_class:       "font-bold text-red",
            exclamation_class: "text-red",
            channels:          @channels
          ),
          status: :not_found
        )
      end
      format.any { render json: { error: I18n.t("pito.not_found.error") }, status: :not_found }
    end
  end
end
