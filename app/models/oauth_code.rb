# frozen_string_literal: true

# A single-use, PKCE-bound authorization code (G130). Minted at consent (POST
# /oauth/authorize) after TOTP approval; exchanged once at POST /oauth/token for
# an access+refresh token pair. Only the code's DIGEST is stored; it expires in
# 5 minutes and can be claimed exactly once.
class OauthCode < ApplicationRecord
  CODE_TTL = 5.minutes

  # Unused and unexpired.
  scope :active, -> { where(used: false).where(expires_at: Time.current..) }

  # Mint a code for a client. Returns [raw_code, record] — the raw code is shown
  # once (redirected to the client); only its digest persists.
  def self.mint(client_id:, redirect_uri:, code_challenge:, code_challenge_method: "S256")
    raw = Pito::Mcp::Oauth.generate_secret
    record = create!(
      client_id:             client_id,
      code_digest:           Pito::Mcp::Oauth.digest(raw),
      code_challenge:        code_challenge,
      code_challenge_method: code_challenge_method,
      redirect_uri:          redirect_uri,
      expires_at:            CODE_TTL.from_now,
      used:                  false
    )
    [ raw, record ]
  end

  # Atomically consume a code by its raw value: find the active record by digest
  # and mark it used (SINGLE-USE — a replay finds nothing). Returns the record or
  # nil. The caller still verifies client_id / redirect_uri / PKCE against the
  # returned record. Only the holder of the raw code can reach this (digest lookup).
  def self.claim(raw_code)
    return nil if raw_code.blank?

    record = active.find_by(code_digest: Pito::Mcp::Oauth.digest(raw_code))
    return nil if record.nil?

    record.update!(used: true)
    record
  end

  # Does this code belong to the presenting client + redirect and satisfy PKCE?
  # All comparisons timing-safe. The controller calls this on the claimed record.
  def valid_exchange?(client_id:, redirect_uri:, code_verifier:)
    Pito::Mcp::Oauth.secure_equal?(self.client_id, client_id) &&
      Pito::Mcp::Oauth.secure_equal?(self.redirect_uri, redirect_uri) &&
      Pito::Mcp::Oauth.pkce_matches?(verifier: code_verifier, challenge: code_challenge)
  end
end
