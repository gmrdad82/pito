# Phase 3 — Step B (5b-token-and-auth-concern.md) — controller-level auth.
#
# Thin shim over `Api::TokenAuthenticator`. Mixed into every `Api::*`
# controller (and intentionally NOT into `ApplicationController` — HTML
# routes stay cookie-based; that's Phase 6/12).
#
# `before_action :authenticate_api_token!` is wired in automatically so
# every action requires a valid bearer token. Each action then calls
# `require_scope!(Scopes::PROJECT_READ)` (or the matching scope) to enforce
# permissions.
#
# Phase 8 — tenant drop. `Current.tenant` is gone. The defense-in-depth
# cross-tenant check is gone too — there is only one install scope.
# A token whose user row has been deleted is still rejected (treated
# as `invalid_token`).
module Api
  module AuthConcern
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_api_token!
    end

    private

    def authenticate_api_token!
      result = Api::TokenAuthenticator.call(request.env)

      if result.failure?
        case result.failure_reason
        when "auth_misconfigured"
          render json: { error: "auth_misconfigured" }, status: :internal_server_error
        when "rate_limited"
          render json: { error: "rate_limited" }, status: :too_many_requests
        else
          raise Api::Unauthorized.new(reason: result.failure_reason)
        end
        return
      end

      token = result.token
      user  = token.user

      if user.nil?
        raise Api::Unauthorized.new(reason: "invalid_token")
      end

      Current.token = token
      Current.user  = user
    end

    # Raise if the current token does not carry the given scope. The
    # concern relies on `authenticate_api_token!` having populated
    # `Current.token`; if `Current.token` is nil we treat it as a
    # programming error (the before_action ordering is wrong) and raise
    # `Api::Unauthorized` rather than crashing.
    def require_scope!(scope)
      token = Current.token
      raise Api::Unauthorized.new(reason: "missing_token") unless token

      return if Array(token.scopes).include?(scope.to_s)

      raise Api::Forbidden.new(required_scope: scope)
    end
  end
end
