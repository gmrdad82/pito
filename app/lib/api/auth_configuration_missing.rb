# Phase 3 — Step B (5b-token-and-auth-concern.md).
#
# 500. The server is misconfigured — typically the `:tokens.pepper`
# credential is missing. Loud failure beats silent fallback.
module Api
  class AuthConfigurationMissing < StandardError
  end
end
