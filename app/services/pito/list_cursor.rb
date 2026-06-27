# frozen_string_literal: true

require "base64"
require "json"

module Pito
  # Opaque keyset-pagination cursor. Encodes an ordered tuple of primitive
  # values — the ordering keys of the "last seen" row — into a single URL-safe
  # token, and decodes it back. Domain-agnostic on purpose: the caller decides
  # what the tuple means (the notifications panel encodes
  # [read_bucket, created_at, id]; a future videos/games list might encode just
  # [created_at, id]). The pager JS never inspects the token — it only echoes the
  # server-built next-page URL — so the cursor's shape stays a server concern.
  module ListCursor
    module_function

    # @param values [Array] ordering-key values for the cursor row
    # @return [String] URL-safe opaque token (no padding)
    def encode(values)
      Base64.urlsafe_encode64(JSON.generate(Array(values)), padding: false)
    end

    # @param token [String, nil]
    # @return [Array, nil] the decoded values, or nil for blank / malformed input
    def decode(token)
      return nil if token.blank?

      parsed = JSON.parse(Base64.urlsafe_decode64(token))
      parsed.is_a?(Array) ? parsed : nil
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end
end
