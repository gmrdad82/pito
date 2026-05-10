# Phase 12 — Step A (6a-sessions-and-login-ui.md) — controller-level
# cookie-session auth.
#
# Replaces the implicit-pin `before_action :set_current_tenant_and_user`
# with a real auth check: every HTML request must arrive with a valid
# `pito_session` cookie. Successful resolution populates
# `Current.session / .user`. Unauthenticated requests are
# redirected to `/login` (with the intended URL stashed in a signed
# cookie for post-login redirect).
#
# Phase 8 — tenant drop. `Current.tenant` is gone; the concern no
# longer pins it.
#
# Allow-listed actions (the login form, the action-screen confirmation
# pages for unauthenticated entry points, the OAuth /authorize screen
# pre-login, etc.) declare `allow_anonymous` at the class level. Those
# actions skip the redirect so they can render their own form.
#
# `Api::*` controllers do NOT include this concern — they continue to
# use `Api::AuthConcern` (bearer-only). The two surfaces stay separate.
module Sessions
  module AuthConcern
    extend ActiveSupport::Concern

    INTENDED_URL_COOKIE = :pito_intended_url
    INTENDED_URL_TTL    = 10.minutes

    included do
      before_action :authenticate_session!
      around_action :reset_current_after_request

      class_attribute :_anonymous_allowed_actions, default: [].freeze
    end

    class_methods do
      # Mark one or more controller actions as "no auth required". Used
      # by `SessionsController` (the login form itself), the OAuth
      # consent screen's pre-login redirect path, and the public health
      # check.
      def allow_anonymous(*actions)
        self._anonymous_allowed_actions = (_anonymous_allowed_actions + actions.map(&:to_sym)).freeze
      end
    end

    private

    def authenticate_session!
      return if anonymous_action?

      result = Sessions::Authenticator.call(request)

      if result.success?
        Current.session = result.session
        Current.user    = result.session.user
        result.session.touch_activity!
        return
      end

      audit_session_cookie_failure(result.reason) if result.reason

      if result.reason == :auth_misconfigured
        render plain: "auth misconfigured", status: :internal_server_error
        return
      end

      stash_intended_url
      redirect_to login_path, alert: "please log in."
    end

    def anonymous_action?
      self.class._anonymous_allowed_actions.include?(action_name.to_sym)
    end

    def stash_intended_url
      return unless request.get?
      return if request.path == login_path
      return if request.path.start_with?("/oauth/") && !request.path.end_with?("/authorize")

      cookies.signed[INTENDED_URL_COOKIE] = {
        value: request.fullpath,
        httponly: true,
        same_site: :lax,
        secure: cookie_secure?,
        expires: INTENDED_URL_TTL.from_now
      }
    end

    def reset_current_after_request
      yield
    ensure
      Current.reset
    end

    # Cookie `secure` flag mirrors the production / dev rule from the
    # locked decision: on in every env except `test` (which runs over
    # plain HTTP via Rack::Test).
    def cookie_secure?
      !Rails.env.test?
    end

    def audit_session_cookie_failure(reason)
      payload = {
        ts: Time.now.utc.iso8601(3),
        event: "session.cookie.invalid",
        reason: reason.to_s,
        ip: request.remote_ip,
        route: "#{request.method} #{request.path}"
      }
      AUTH_AUDIT_LOGGER.info(payload.to_json) if defined?(AUTH_AUDIT_LOGGER)
    rescue StandardError
      nil
    end
  end
end
