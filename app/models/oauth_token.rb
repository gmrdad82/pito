# frozen_string_literal: true

# An MCP OAuth token pair. The owner authenticates (one TOTP) exactly once
# per client at consent; thereafter the client refreshes silently. So:
#   * the ACCESS token is short-lived (24h) and ROTATES on refresh;
#   * the REFRESH token NEVER expires — only explicit revocation (revoked_at) kills
#     it (owner rule: "authenticate once").
# Both are stored as digests only; verification is timing-safe.
class OauthToken < ApplicationRecord
  ACCESS_TTL = 24.hours

  # Active = not revoked AND the access token is still within its window. (Refresh
  # validity is checked separately in .refresh! — refresh ignores expires_at.)
  scope :active, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  # Issue a fresh access+refresh pair for a client (after a successful code
  # exchange). Returns [access_raw, refresh_raw, record]; only digests persist.
  def self.issue(client_id:)
    access  = Pito::Mcp::Oauth.generate_secret
    refresh = Pito::Mcp::Oauth.generate_secret
    record  = create!(
      client_id:      client_id,
      token_digest:   Pito::Mcp::Oauth.digest(access),
      refresh_digest: Pito::Mcp::Oauth.digest(refresh),
      expires_at:     ACCESS_TTL.from_now
    )
    [ access, refresh, record ]
  end

  # Resolve a presented Bearer ACCESS token to its active record, or nil. The
  # digest lookup is the match; there is no raw secret to compare.
  def self.authenticate(raw_access)
    return nil if raw_access.blank?

    active.find_by(token_digest: Pito::Mcp::Oauth.digest(raw_access))
  end

  # Rotate the access token from a raw REFRESH token (refresh never expires; only
  # revocation kills it). Returns [new_access_raw, record] or nil.
  def self.refresh!(raw_refresh)
    return nil if raw_refresh.blank?

    record = where(revoked_at: nil).find_by(refresh_digest: Pito::Mcp::Oauth.digest(raw_refresh))
    return nil if record.nil?

    new_access = Pito::Mcp::Oauth.generate_secret
    record.update!(token_digest: Pito::Mcp::Oauth.digest(new_access), expires_at: ACCESS_TTL.from_now)
    [ new_access, record ]
  end
end
