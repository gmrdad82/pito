# Phase 09 — Login-with-Google Drop · Log

## 2026-05-10 — Architect spec landed

Architect spec landed at
`docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`.

The spec covers:

- Removing the dormant sign-in-with-Google branch from
  `Auth::GoogleCallbacksController#create` and the `GoogleOauthRedirect` helper
  so `/auth/google/callback` exists exclusively for the channel-connection flow.
- Renaming `GoogleIdentity` → `YoutubeConnection` (model, table, factories,
  every reference site).
- Renaming the Channel/Video association column `oauth_identity_id` →
  `youtube_connection_id` and the matching helpers.
- Extending `User` from `has_one :google_identity` (implicit via the current
  uniqueness constraint per user) to
  `has_many :youtube_connections, dependent: :destroy`.
- Reseeding via the destructive-and-reseed posture inherited from ADR 0003
  (Phase 8) — no production data, no backfill.
- Full RSpec sweep + new test cases covering the rename and the
  channel-connection flow's edges.

Implementation lane to follow once master agent dispatches.

**Cross-references:**

- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/realignment-2026-05-09.md`
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/`
