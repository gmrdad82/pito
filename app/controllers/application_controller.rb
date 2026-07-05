class ApplicationController < ActionController::Base
  # Cookie-backed session auth. Anonymous-allowed actions (the login form,
  # OAuth pre-login entry points) declare themselves via `allow_anonymous`
  # at the class level.
  include Sessions::AuthConcern

  # CSRF carve-out for non-browser clients (pito-tui et al.): requests whose
  # BODY is application/json skip the authenticity token. Safe because the
  # token defends against forged BROWSER submissions, and no browser vector
  # can produce this content type against us: an HTML form can only send
  # urlencoded/multipart/text-plain, a cross-origin fetch with a JSON body
  # triggers a CORS preflight we never approve, and the session cookie is
  # SameSite=lax so cross-site POSTs arrive unauthenticated anyway. Keyed on
  # request.media_type (the Content-Type header), NOT request.format — format
  # is attacker-influencable via the URL (.json / ?format=), media_type only
  # via a non-form request body.
  skip_forgery_protection if: -> { request.media_type == "application/json" }

  # UTC-storage / user-tz-render is the app-wide contract. All requests
  # render times in the owner's configured time zone (AppSetting.timezone,
  # default UTC). ActiveRecord keeps storing UTC internally.
  before_action :set_user_time_zone

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # HTML documents are NEVER cached (G84): the Android WebView re-served a
  # cached page on pull-to-refresh — content looked fresh (the scrollback
  # streams from the cable/DB) but the document still referenced the OLD
  # fingerprinted CSS, so a server update never restyled. Rails' default
  # max-age=0/must-revalidate is advisory enough for browsers but WebViews
  # skip revalidation on reload; no-store removes the discretion. Assets are
  # untouched (fingerprinted, 1y immutable via public_file_server).
  after_action :forbid_html_caching

  def forbid_html_caching
    response.headers["Cache-Control"] = "no-store" if request.format.html?
  end
  private :forbid_html_caching

  helper_method :current_conversation
  helper_method :hotwire_native_app?

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

  # True when the request comes from the Hotwire Native shell (the Android
  # app sets "Hotwire Native" in its User-Agent). Lets server-rendered chrome
  # adapt — e.g. never advertise the app to someone already inside it.
  def hotwire_native_app?
    request.user_agent.to_s.include?("Hotwire Native")
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

    # SHOWCASE-START-NOTFOUND: seed suggestions for authenticated users only.
    initial_showcase = Current.session.present? ? Pito::Showcase::Builder.call(conversation: nil) : []

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
            channels:          @channels,
            suggestions:       initial_showcase
          ),
          status: :not_found
        )
      end
      format.any { render json: { error: I18n.t("pito.not_found.error") }, status: :not_found }
    end
  end
end
