# frozen_string_literal: true

module Pito
  module Mcp
    # Bearer-token authentication for the MCP endpoint. The controller extracts the
    # `Authorization: Bearer <token>` value and asks this seam to resolve it to the
    # OAuth client it was minted for; nil means "reject" (401 + WWW-Authenticate).
    #
    # SECURE BY DEFAULT: until P4 wires the oauth_tokens digest lookup, no token
    # resolves, so every request is rejected. P4 replaces the body of #authenticate
    # with a timing-safe digest comparison against unrevoked, unexpired tokens.
    module Auth
      module_function

      # @param token [String, nil] the raw Bearer access token
      # @return [OauthToken, nil] the active token record (truthy) or nil to reject
      def authenticate(token)
        return nil if token.blank?

        # Digest lookup against unrevoked, unexpired access tokens (never a raw
        # secret at rest). See OauthToken.authenticate.
        OauthToken.authenticate(token)
      end
    end
  end
end
