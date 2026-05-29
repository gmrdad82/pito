# Encrypted-cookie session auth.
#
# Reads `Pito::Auth::SessionCookie` on every request. If the cookie is
# valid (not expired, not tampered) populates `Current.session` with a
# `SessionData` value object. If absent or expired, redirects to the
# root chat shell, where the owner authenticates by typing
# `/authenticate <code>` (there is no /login route).
#
# Anonymous-allowed actions (the root chat shell, health check) skip the
# redirect but still opportunistically load a valid session so the
# layout can render the authenticated state.
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
      def allow_anonymous(*actions)
        self._anonymous_allowed_actions = (_anonymous_allowed_actions + actions.map(&:to_sym)).freeze
      end
    end

    private

    def authenticate_session!
      cookie_manager = Pito::Auth::SessionCookie.new(request)
      data = cookie_manager.read

      if data
        Current.session = cookie_manager.touch!(data)
        return
      end

      # Anonymous actions proceed without a session — the layout shows
      # the unauthenticated (Anonymous) state.
      return if anonymous_action?

      stash_intended_url
      redirect_to root_path, alert: "authenticate first: /authenticate <code>"
    end

    def anonymous_action?
      self.class._anonymous_allowed_actions.include?(action_name.to_sym)
    end

    def stash_intended_url
      return unless request.get?
      return if request.path == root_path
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

    def cookie_secure?
      !Rails.env.test?
    end
  end
end
