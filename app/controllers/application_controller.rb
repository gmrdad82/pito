class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Phase 12 — Step A (6a-sessions-and-login-ui.md). Cookie-backed
  # session auth replaces the implicit `set_current_tenant_and_user`
  # pin. Anonymous-allowed actions (the login form, OAuth's pre-login
  # entry point) declare themselves via `allow_anonymous` at the class
  # level. The concern owns the `before_action`, the unauthenticated
  # redirect, and the `Current` reset.
  include Sessions::AuthConcern

  # Phase 26 — 01a. Timezone foundation. UTC-storage / user-tz-render
  # is the app-wide contract; every request renders times in the
  # authenticated user's `time_zone`. Unauthenticated requests
  # (the login form, OAuth pre-login screens) fall back to `Etc/UTC`.
  # `Sessions::AuthConcern` runs first and populates `Current.user`
  # so this hook always sees the resolved user when present.
  before_action :set_user_time_zone

  # Translate ActiveRecord::RecordNotFound into a clean JSON 404 for JSON
  # requests so the pito CLI (and any other JSON consumer) gets a parseable
  # error body instead of an HTML error page. HTML still returns a plain 404
  # page.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Phase 3 — Step B. Auth errors raised from `Api::AuthConcern` /
  # `Api::TokenAuthenticator` translate into the standard JSON envelopes.
  # The HTML routes never raise these (they don't include the concern), so
  # the rescues are a safety net rather than a hot path.
  rescue_from Api::Unauthorized, with: :render_api_unauthorized
  rescue_from Api::Forbidden,    with: :render_api_forbidden

  private

  # Phase 26 — 01a. Pin `Time.zone` for the duration of the request to
  # the authenticated user's stored zone. Rails' per-request reset
  # mechanism (CurrentAttributes + the around_action in
  # `Sessions::AuthConcern`) clears `Current.*` after the request, but
  # `Time.zone` is set on `Thread.current` and would otherwise leak.
  # Setting it here per request is the safe pattern Rails docs
  # recommend (see ActiveSupport::TimeZone docs). Unauthenticated
  # requests fall back to `Etc/UTC` so the render-layer helpers stay
  # nil-safe on the login form and OAuth pre-login screens.
  def set_user_time_zone
    Time.zone = Current.user&.time_zone.presence || "Etc/UTC"
  end

  def render_not_found
    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any  { render plain: "Not found", status: :not_found }
    end
  end

  def render_api_unauthorized(error)
    # Phase 7.5 — MCP OAuth discovery. Mirror the Rack-app 401 by
    # advertising the OAuth metadata locations on every controller
    # 401, so Claude.ai's MCP custom connector and any other
    # OAuth-aware bearer client can discover the dance from a single
    # rejected call regardless of which surface refused them.
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
