# Phase 3 — Step B (5b-token-and-auth-concern.md).
#
# 403. The bearer token is valid but lacks the scope the action needs.
# `required_scope` is reported back in the JSON body so callers know
# which permission to mint.
module Api
  class Forbidden < StandardError
    attr_reader :required_scope

    def initialize(required_scope:, message: nil)
      @required_scope = required_scope.to_s
      super(message || "insufficient_scope: #{@required_scope}")
    end
  end
end
