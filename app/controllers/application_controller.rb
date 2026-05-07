class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Populate Current with the seeded singleton tenant / user before every
  # request, per docs/architecture.md. This is the placeholder implementation
  # for the single-tenant single-user world; Phase 5 replaces it with proper
  # tenant/user resolution from a session or token.
  before_action :set_current_tenant_and_user

  # Translate ActiveRecord::RecordNotFound into a clean JSON 404 for JSON
  # requests so pito-sh (and any other JSON consumer) gets a parseable error
  # body instead of an HTML error page. HTML still returns a plain 404 page.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Phase 3 — Step B. Auth errors raised from `Api::AuthConcern` /
  # `Api::TokenAuthenticator` translate into the standard JSON envelopes.
  # The HTML routes never raise these (they don't include the concern), so
  # the rescues are a safety net rather than a hot path.
  rescue_from Api::Unauthorized, with: :render_api_unauthorized
  rescue_from Api::Forbidden,    with: :render_api_forbidden

  private

  def set_current_tenant_and_user
    Current.tenant = Tenant.first
    Current.user   = User.first
  end

  def render_not_found
    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any  { render plain: "Not found", status: :not_found }
    end
  end

  def render_api_unauthorized(error)
    render json: { error: error.reason }, status: :unauthorized
  end

  def render_api_forbidden(error)
    render json: {
      error: "insufficient_scope",
      required: error.required_scope
    }, status: :forbidden
  end
end
