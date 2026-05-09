# ADR 0006 — Drop "Sign in with Google": Channel-Only Google OAuth

## Status

Accepted, 2026-05-10.

## Context

Phase 7 (`docs/plans/beta/07-google-oauth-youtube-foundation/`) introduced a
`GoogleIdentity` model that doubled as both a user-identity record (the
foundation for "Sign in with Google" on the login page) and a YouTube API grant
holder (encrypted access / refresh tokens, scopes, `needs_reauth` state). The
dual role made `GoogleIdentity` the linchpin between authentication and the
YouTube Data / Analytics API surface.

Two adjacent decisions made the dual role obsolete:

- **ADR 0003** dropped tenant scoping in favor of single-install + multi-user.
  The product is now positioned explicitly as a personal / self-hosted creator
  workflow, not a SaaS surface where third-party identity providers earn their
  keep.
- **Phase 6A** shipped local-password sessions (DB-backed `sessions` table,
  `bcrypt` digests, `/login`, `/logout`, `/settings/sessions` revocation). The
  local-password path is the canonical authentication route for every install.

With local auth landed and the SaaS framing retired, the "Sign in with Google"
button on the login page adds complexity (a second authentication code path, a
`GoogleIdentity → User` linking flow, a Google-account-as-user-identity data
shape) without giving the install operator anything they don't already have.
Google OAuth's remaining value is the YouTube API grant — the OAuth dance is
what authorizes pito to talk to YouTube on the install's behalf.

The user's direction on 2026-05-10 ("We don't need Login with Google anymore. We
do need to connect with Google to our channels though.") locks the decision:
keep the OAuth dance for YouTube channel connection; drop it as an identity
provider.

## Decision

Drop "Sign in with Google" entirely. Repurpose Google OAuth purely for
**connecting YouTube channels** (granting API access). The login page offers
local password auth only.

Concretely:

- The login page (`/login`) shows email + password fields and a submit. No
  third-party identity provider buttons.
- Google OAuth lives behind a `[ connect youtube channel ]` action that an
  authenticated user invokes from a channels page (or a Settings surface). The
  OAuth dance returns an access / refresh token pair; the resulting record
  represents a "YouTube connection," not a user identity.
- One Google account (one OAuth grant) maps to potentially many channels under
  that account. The connection is keyed by the Google account, not by an
  individual channel.

## Consequences

- **`GoogleIdentity` model's role narrows** to "YouTube API connection." The
  model name is now misleading — it implies user identity. Likely renamed to
  `YoutubeConnection` (or similar) when the architect revises the Phase 7 spec;
  the rename is the architect's call, not this ADR's.
- **Login page removes the "Sign in with Google" button.** Phase 6 sessions stay
  local-password. No OmniAuth callback wires identity to a session.
- **Channel connection flow.** The user authenticates locally first (`/login`),
  then triggers `[ connect youtube channel ]` (or equivalent). The Google OAuth
  dance launches; on success, the granted tokens persist on the connection
  record; channels imported from that grant attach to the connection.
- **Phase 7 spec gets revised** to reflect connection-only OAuth. That revision
  is a separate dispatch (architect-spec), not part of this docs sweep.
- **Per-user Google connections vs. install-level.** With ADR 0003's
  single-install + multi-user shape, the connection is install-level by default.
  Multiple users can act against the same set of YouTube channels through the
  same connection. Per-user connections are a future option, not a v1
  requirement.
- **Doorkeeper / `/settings/oauth_applications`** is unaffected. ADR 0005 keeps
  Doorkeeper for Claude Mobile + Web MCP. Doorkeeper handles third-party MCP
  clients connecting INTO pito; Google OAuth handles pito connecting OUT to
  YouTube. Different surfaces, different lifecycles.

## Why this is right for pito

- Pito is a personal-install creator tool. The install operator already has a
  local user account (Phase 6A). A second identity provider buys nothing.
- Local auth is the canonical path. Every install has it. Google OAuth would be
  optional — and an optional auth path means an extra code path to maintain, an
  extra failure mode to support.
- Google OAuth is an integration, not an identity provider. The thing pito
  actually needs from Google is API authorization to read / write YouTube
  channels and videos. Modeling that as a "connection" is the honest shape;
  modeling it as a user-identity record was a Phase 7 expedient that no longer
  earns its keep.

## Alternatives considered

- **Keep "Sign in with Google" alongside local auth.** Rejected. Two parallel
  authentication paths in a single-install tool with no SaaS aspirations is pure
  complexity tax. Every change to one path forces a parity check on the other.
- **Drop Google OAuth entirely, manage YouTube via API key.** Rejected. YouTube
  Data API v3 + Analytics API v2 require user-context OAuth tokens for the
  management workflows pito needs (writing video metadata, reading private
  analytics). API keys cover only public-data reads.
- **Keep `GoogleIdentity` name, just stop using it for sign-in.** Rejected as
  half-measure. The name encodes the dual role; collapsing the role without
  renaming the model leaves the misleading framing in code.

## Date

2026-05-10.

## Related

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
  install + multi-user direction that makes third-party identity providers
  unnecessary.
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — Doorkeeper
  surface stays; orthogonal to this decision.
- `docs/plans/beta/07-google-oauth-youtube-foundation/` — Phase 7 spec gets
  revised in a follow-up architect dispatch to reflect connection-only OAuth.
- `docs/realignment-2026-05-09.md` — Resolved ambiguities section captures this
  decision in the realignment trail.
