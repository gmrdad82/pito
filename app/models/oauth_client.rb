# frozen_string_literal: true

# A registered MCP OAuth client. PUBLIC client — no client_secret; PKCE is
# the proof-of-possession. Created via RFC 7591 dynamic registration (claude.ai
# self-registers). The `client_id` is the only credential and is not itself a
# secret (PKCE binds the authorization to the requesting client).
class OauthClient < ApplicationRecord
  validates :client_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :redirect_uris, presence: true

  # Register a new public client. Returns the persisted record (its client_id is
  # a fresh random identifier).
  def self.register(name:, redirect_uris:)
    create!(
      client_id:     Pito::Mcp::Oauth.generate_secret,
      name:          name.to_s.presence || "MCP client",
      redirect_uris: Array(redirect_uris).map(&:to_s)
    )
  end

  # Exact-match redirect URI check (no wildcard/prefix matching — an open
  # redirect is a token-exfiltration vector).
  def allows_redirect?(uri)
    redirect_uris.include?(uri.to_s)
  end
end
