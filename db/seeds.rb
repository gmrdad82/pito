# frozen_string_literal: true

# No default seeds — content is bootstrapped from real data.
# Use `bin/rails pito:tools:backup` to capture a full backup (db + Voyage
# embeddings + ActiveStorage assets) into backup/<timestamp>/. Restore is manual.

# ── Sample notifications (idempotent) ──────────────────────────────────────────
#
# Creates 3 sample notifications for browser smoke testing. Guarded by message
# uniqueness so re-running `bin/rails db:seed` does not duplicate them.
[
  {
    message:    "Your video sync completed successfully.",
    read_at:    nil,
    created_at: 5.minutes.ago
  },
  {
    message:    "New channel milestone: 1 000 subscribers reached!",
    read_at:    nil,
    created_at: 3.hours.ago
  },
  {
    message:    "Weekly digest is ready for review.",
    read_at:    2.days.ago,
    created_at: 2.days.ago
  }
].each do |attrs|
  next if Notification.exists?(message: attrs[:message])

  Notification.create!(attrs.merge(updated_at: attrs[:created_at]))
end

# ── Demo MCP OAuth client — DEVELOPMENT ONLY (idempotent) ───────────────────────
#
# A fixed public client so the `mkt-mcp` capture scenario can render the /oauth
# consent page ("Authorize Claude") for the pitomd landing shot. NEVER seeded in
# production — a standing registered client there is a token-exfiltration surface;
# real clients self-register via RFC 7591 dynamic registration. The client_id is
# fixed (not a secret — PKCE binds the grant); its only use is the capture URL in
# lib/support/pitomd/mkt-mcp.yml.
if Rails.env.development? && !OauthClient.exists?(client_id: "mkt-capture-demo")
  OauthClient.create!(
    client_id:     "mkt-capture-demo",
    name:          "Claude",
    redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ]
  )
end
