# frozen_string_literal: true

require "digest"
require "base64"

module Pito
  module Mcp
    # Cryptographic helpers for the hand-rolled OAuth 2.1 flow. The invariant the
    # whole design leans on: pito NEVER stores a raw secret — codes, access tokens,
    # and refresh tokens are persisted only as SHA-256 digests, and every
    # comparison is timing-safe.
    module Oauth
      module_function

      TOKEN_BYTES = 32

      # A high-entropy, URL-safe secret (the raw code / access / refresh token —
      # shown to the client ONCE; only its digest is stored).
      def generate_secret
        SecureRandom.urlsafe_base64(TOKEN_BYTES)
      end

      # The at-rest form of a secret.
      def digest(raw)
        Digest::SHA256.hexdigest(raw.to_s)
      end

      # Timing-safe string equality (secure_compare requires equal-length inputs;
      # it returns false on a length mismatch instead of raising).
      def secure_equal?(left, right)
        left = left.to_s
        right = right.to_s
        return false if left.bytesize != right.bytesize

        ActiveSupport::SecurityUtils.secure_compare(left, right)
      end

      # PKCE S256: the stored `code_challenge` must equal base64url(sha256(verifier)),
      # unpadded (RFC 7636 §4.2). Compared timing-safe.
      def pkce_matches?(verifier:, challenge:)
        return false if verifier.blank? || challenge.blank?

        computed = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
        secure_equal?(computed, challenge)
      end
    end
  end
end
