# ADR 0007 — YouTube credentials moved from `Rails.application.credentials` to `AppSetting` (Active Record Encryption)

> **Superseded by ADR 0012**
> (`docs/decisions/0012-revert-appsetting-credentials-to-rails-credentials.md`,
> 2026-05-15). Phase 29 Unit A1 reverted YouTube + Voyage + Google console
> credentials back to `Rails.application.credentials` after the hot-rotation
> benefit this ADR promised never materialized (the omniauth middleware kept
> reading at boot). The body below is preserved as historical record.

## Status

Accepted, 2026-05-11. Superseded by ADR 0012 on 2026-05-15. [skipci]

## Context

Phase 7 (`docs/plans/beta/07-google-oauth-youtube-foundation/`) wired pito to
read its YouTube OAuth + API credentials from
`Rails.application.credentials.google_oauth`. That block carried four keys:
`project_id`, `client_id`, `client_secret`, `api_key` (and later
`redirect_uri`).

The credentials-file path worked for a one-developer install, but it has two
operational drawbacks:

- **Rotation requires a deploy.** Changing the OAuth client or the API key means
  running `bin/rails credentials:edit`, re-encrypting the file, and redeploying.
  There is no in-product surface for the operator to swap credentials.
- **Pattern mismatch with Voyage.** Phase 4 Phase B already moved the Voyage API
  key onto the `AppSetting` singleton row, encrypted via Active Record
  Encryption, with a web-form rotation surface under `/settings`. The YouTube
  credentials sat in a parallel-but-different storage pattern, which forced the
  Settings UI to render two different "credentials configured" surfaces and
  forced any docs sweep to explain two different rotation paths.

The Phase 27 settings revamp made the inconsistency visible (the YouTube pane
had to render `youtube_credentials_status` from a helper that read a credentials
block while the Voyage pane right next to it read AppSetting columns directly).

## Decision

Move YouTube OAuth + API credentials onto the `AppSetting` singleton row.

Concretely:

- Migration `20260511153000_add_youtube_credentials_to_app_settings` adds four
  columns to `app_settings`: `youtube_api_key`, `youtube_client_id`,
  `youtube_client_secret`, `youtube_redirect_uri`.
- `app/models/app_setting.rb` declares
  `encrypts :youtube_api_key, :youtube_client_secret` (non-deterministic —
  sensitive, never compared / queried). The client ID and redirect URI stay
  plaintext because both are exposed in normal OAuth round-trips and benefit
  from being read-able in the Settings UI without decryption gymnastics.
- The Settings YouTube pane is rebuilt in the Voyage-style shape: a single form
  with the four fields, per-field clear checkboxes (yes/no boundary), and the
  same "credentials stored encrypted in the database; never echoed" hint copy.
  Configured-but-not-shown fields render `key configured (•••••••)` placeholders
  via per-field `*_configured?` predicates on `AppSetting`.
- `config/initializers/omniauth.rb` is updated to a 4-tier resolver:
  1. `AppSetting` singleton column (UI-edited; primary).
  2. `Rails.application.credentials.google_oauth` block (legacy fallback, kept
     as a manual revert path).
  3. `PITO_GOOGLE_OAUTH_*` ENV vars (CI / local-no-DB workflows).
  4. Test-mode placeholder so request specs boot without `master.key` AND
     without a populated `AppSetting`.
- `Youtube::PublicClient` and `Youtube::TokenRefresher` are updated to read from
  `AppSetting` first, falling back to the credentials block.
- `lib/tasks/youtube_credentials_backfill.rake` is added — one idempotent task
  `pito:backfill_youtube_credentials` that seeds the AppSetting columns from the
  credentials block on the first deploy. Never overwrites an already-set column.

The legacy `Rails.application.credentials.google_oauth` block is deliberately
NOT removed. It stays on disk as a one-line manual revert path: if the
`AppSetting` row is wiped (DB restore, migration disaster, etc.), the legacy
fallback chain keeps the OAuth surface alive while the operator reseeds the
singleton.

Active Record Encryption keys themselves (`primary_key`, `deterministic_key`,
`key_derivation_salt`) stay in `Rails.application.credentials`. The
sensitive-credential-storage primitive moved; the encryption key storage did
not.

## Consequences

- **Operator can rotate YouTube credentials without a deploy.** Settings →
  YouTube → fill the form → submit → restart Puma. (Hot rotation without a
  restart is a documented follow-up — the omniauth middleware reads its config
  at boot.)
- **Two storage patterns collapse into one.** Voyage and YouTube live on the
  same row, encrypted the same way, surfaced the same way in the Settings pane.
  Future integration credentials (Slack, Discord, IGDB, …) inherit the same
  shape.
- **Pre-existing installs migrate via the rake task.** The first deploy after
  this change runs `bin/rails pito:backfill_youtube_credentials` once. No
  downtime; the backfill is idempotent.
- **The Settings UI surfaces the configured state honestly.** Per-field
  `*_configured?` predicates avoid the "is this credential set or not" guess the
  old credentials-block path had to do via a helper.
- **`omniauth.rb` resolver complexity grows.** Four tiers instead of one. The
  resolver is documented in the file header and is the canonical rotation
  surface — future contributors edit it when adding a new fallback tier, not the
  model.

## Open question (deferred)

When (and whether) to remove the legacy
`Rails.application.credentials.google_oauth` block from `credentials.yml.enc`.
The block is the only revert path the omniauth initializer has if the
`AppSetting` row is corrupted; keeping it costs nothing on disk but does mean
two credential stores can drift if an operator edits the credentials file but
not the AppSetting form (or vice versa). The current posture is "leave it;
document it as revert-only". Revisit once the AppSetting form has at least one
successful production rotation logged.

## Alternatives considered

- **Keep credentials in `Rails.application.credentials.google_oauth`, surface
  rotation via a `bin/rails credentials:edit` walkthrough.** Rejected. The point
  of the move is to eliminate the deploy-to-rotate workflow; the walkthrough is
  the workflow we're trying to retire.
- **Move credentials to ENV.** Rejected. ENV is the right surface for
  infrastructure connection info (host / port), not for OAuth secrets. The hard
  rule in `CLAUDE.md` ("secrets live exclusively in
  `Rails.application.credentials`") was rewritten in this change to extend the
  secret-storage surface to `AppSetting` (encrypted at rest via Active Record
  Encryption) — ENV remains explicitly off-limits.
- **Net-new `youtube_credentials` table.** Rejected. The `AppSetting` singleton
  already exists for exactly this kind of operator-managed configuration row. A
  second table would mean a second migration, a second rotation form, a second
  set of `*_configured?` predicates. The singleton is the canonical shape; the
  per-feature columns ride along.

## Date

2026-05-11. [skipci]

## Related

- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` — scopes
  Google OAuth to YouTube-only; the credentials this ADR moves are the
  credentials that OAuth dance uses.
- `docs/architecture.md` → "Cloud Console linkage" — runtime resolution order
  and field semantics.
- `docs/setup.md` → "Persist credentials into Rails" — operator-facing setup +
  backfill walkthrough.
- `lib/tasks/youtube_credentials_backfill.rake` — the idempotent migration task.
- `app/models/app_setting.rb` — `encrypts` declarations + per-field
  `*_configured?` predicates.
