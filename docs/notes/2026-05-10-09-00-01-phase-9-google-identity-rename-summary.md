# Phase 9 — Drop sign-in-with-Google + GoogleIdentity → YoutubeConnection rename

## Status

**Landed.** Implementation + reviewer + security + prose rewrites all in `main`.
Awaiting your manual validation.

## What changed

- `GoogleIdentity` model + `google_identities` table renamed to
  `YoutubeConnection` + `youtube_connections`.
- `oauth_identity_id` FK on `channels` and `videos` renamed to
  `youtube_connection_id`. Same on `youtube_api_calls` (was
  `google_identity_id`).
- Sign-in-with-Google dormant code removed (`Auth::GoogleCallbacksController`
  deleted; `/auth/google` dev redirect retired). Login is local email + password
  only.
- Stale-callback flash:
  `sign-in via google is not supported. log in with email and password.`
- Audit-log keys added:
  `youtube_connection.callback.{succeeded,failed,stale_intent}`.
- Session intent key renamed: `:google_oauth_intent` →
  `:youtube_connection_oauth_intent`.
- `User has_many :youtube_connections, dependent: :destroy`.
  `YoutubeConnection has_many :channels, dependent: :nullify` (channels outlive
  connections — Phase 7C disconnect-lifecycle preserved).
- Migration: `rename_table` + `rename_column` + `rename_index`. No rollback
  support (destructive-and-reseed posture per ADR 0003).

## Quality gates

- 1673 RSpec examples → 0 failures (net +10 from Phase 8 baseline).
- Rubocop clean.
- Brakeman clean.

## Reviewer playbook

`docs/orchestration/playbooks/2026-05-10-phase-9-google-identity-rename.md`

## Security findings

`docs/orchestration/playbooks/security-2026-05-10-phase-9-google-identity-rename.md`
— Verdict: CLEAR TO MERGE. 0 phase-9-introduced findings. 1 pre-existing medium
(F1: cross-user token overwrite if two pito users share a Google account),
tracked as Phase 11+ follow-up.

## Validation steps when you're back

1. After Phase 8's `db:seed`, no extra setup needed.
2. Visit `/settings/youtube`. Confirm renders. Connect a YouTube channel (start
   the OAuth flow). Confirm a `YoutubeConnection` row is created.
3. Confirm channel imported under that connection has `youtube_connection_id`
   populated.
4. Disconnect channel → confirm `youtube_connection_id` nullifies (channel row
   survives, ready for re-connect).
5. While logged in, hit `/auth/google/callback` directly with no session intent
   → confirm stale-intent flash.
6. `bin/rails routes | grep auth/google` → only `/auth/google/callback` and
   `/auth/failure`. No `/auth/google` redirect.

## Open follow-ups (non-blocking)

- **F1** — change unique index from `google_subject_id` only to
  `(user_id, google_subject_id)` so two pito users can each connect the same
  Google account without overwriting each other. Phase 11+ scope.
- Reviewer concern #1 — OAuth scope gap (`/connect` doesn't request
  `youtube.readonly`). Phase 11's job per locked Phase 9 / 11 boundary. YouTube
  API calls will surface "youtube api unavailable" until Phase 11.
- F4 — `Google::RevokeToken` synchronous HTTP inside AR transaction
  (pre-existing Phase 7C-era concern).
- Brakeman ignore-file housekeeping (2 obsolete entries).
