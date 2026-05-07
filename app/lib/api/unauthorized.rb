# Phase 3 — Step B (5b-token-and-auth-concern.md).
#
# 401. Bearer token was missing, malformed, unknown, revoked, or expired.
# `reason` matches the audit-log event suffix
# (`missing_token`, `invalid_token`, `revoked_token`, `expired_token`).
module Api
  class Unauthorized < StandardError
    attr_reader :reason

    def initialize(reason: "invalid_token", message: nil)
      @reason = reason.to_s
      super(message || @reason)
    end
  end
end
