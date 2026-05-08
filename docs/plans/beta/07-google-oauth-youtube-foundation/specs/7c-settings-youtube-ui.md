# Phase 7 — Step 7C — Settings → YouTube UI and Channel Connection Flow

> Third of three Phase 7 specs. Lights up the user-visible Settings → YouTube
> sub-page, the channel connect/disconnect actions, and the "needs reauth"
> banner. Depends on 7A (`GoogleIdentity` + OAuth callback) and 7B
> (`YouTube::Client#channels_list`). Locked decisions are pinned exactly — do
> not reinvent.

---

## Goal

Surface the YouTube connection flow inside Settings. After a user authorizes
their Google account (7A), this page lists the user's owned YouTube channels
(fetched via 7B's `YouTube::Client#channels_list(mine: true)`), lets them
connect any channel into Pito's existing `Channel` table with a `[ connect ]`
bracketed link, lets them disconnect with a confirmation page (per the
`Confirmable` framework), and surfaces a "needs reauth" banner when
`GoogleIdentity#needs_reauth?` is true.

This is the only user-facing UI Phase 7 ships. It uses no JavaScript dialogs, no
Turbo Streams beyond what's already standard, and no decoration the design
system doesn't already cover.

## Files touched

Rails (Lane 1):

- `config/routes.rb` — `/settings/youtube` (show), the existing
  `/settings/youtube/connect` (kicked off in 7A), per-channel connect/
  disconnect endpoints (see §"Routes").
- `app/controllers/settings/youtube_controller.rb` — show + create/connect
  actions.
- `app/controllers/deletions_controller.rb` — extend to handle the
  `youtube_connection` deletion type (per the bulk-as-foundation rule); a
  "deletion" of a YouTube connection is the disconnect flow.
- `app/models/channel.rb` — add `oauth_identity_id`, `connected` columns
  (migration below); update `belongs_to :oauth_identity`, optional.
- `db/migrate/<ts>_add_oauth_identity_to_channels.rb` — adds `oauth_identity_id`
  (fk to `google_identities`, nullable) and `connected` (boolean, not null,
  default `false`) to the existing `channels` table. Existing seeded channels
  stay `connected: false`, `oauth_identity_id: nil`.
- `app/services/youtube/disconnect_channel.rb` — disconnect logic: clear
  `oauth_identity_id` + `connected` on the Channel, conditionally revoke the
  Google grant if no other Channels reference the identity.
- `app/services/google/revoke_token.rb` — POST to
  `https://oauth2.googleapis.com/revoke`, audit (writes a `YoutubeApiCall` row
  with `client_kind: "oauth"`, `endpoint: "oauth2.revoke"`, `units: 0`).
- `app/views/settings/youtube/show.html.erb` — the page.
- `app/views/settings/youtube/_channel_row.html.erb` — one row per fetched
  YouTube channel.
- `app/views/settings/youtube/_needs_reauth_banner.html.erb`.
- `app/views/shared/_action_screen.html.erb` — already exists; reused for the
  disconnect confirmation page.
- `app/views/layouts/_settings_nav.html.erb` — add the Settings → YouTube nav
  entry as a `[ youtube ]` bracketed link (or whatever Phase 4 settings nav
  settled on; verify against `docs/design.md`).
- `spec/requests/settings/youtube_spec.rb`
- `spec/services/youtube/disconnect_channel_spec.rb`
- `spec/services/google/revoke_token_spec.rb`
- `spec/system/settings_youtube_spec.rb`

Documentation (parallel docs-keeper dispatch — out of this spec's lane):

- `docs/design.md` — Settings → YouTube section: bracketed table layout,
  `[ connect ]` / `[ disconnect ]` row actions, `needs reauth` banner shape.
  Also: append a one-line note to the color section documenting the carve-out
  for failure-state banners (red allowed; see §"Decisions (locked)" below). This
  is a TODO-on-implementation handed to the docs-keeper dispatch — this spec
  does NOT edit `docs/design.md` directly.

Cross-stack scope: Rails-only.

## Schema delta

`channels` table — add two columns (new migration):

| Column            | Type    | Constraints                      |
| ----------------- | ------- | -------------------------------- |
| oauth_identity_id | bigint  | nullable, fk → google_identities |
| connected         | boolean | not null, default `false`        |

Indexes:

- `(tenant_id, oauth_identity_id)` non-unique — used by the disconnect path to
  check "is anyone else still using this identity?".
- `(tenant_id, connected)` partial where `connected = true` — fast filter for
  "all connected channels under this tenant".

`Channel` model:

- `belongs_to :oauth_identity, class_name: "GoogleIdentity", optional: true`
- `scope :connected, -> { where(connected: true) }`
- The existing `prevent_url_change` `before_update` rule (per `CLAUDE.md`) is
  unchanged. `oauth_identity_id` and `connected` are mutable.

Channel **identity / lookup** for the connect flow uses
`channel_url == "https://www.youtube.com/channel/<channel_id>"`. The connect
action builds that URL from the YouTube channel id and `find_or_create_by` on
`(tenant_id, channel_url)`. The `channel_url` lock applies only on update;
create is fine.

## Routes

```
GET    /settings/youtube                                        → show
POST   /settings/youtube/connect                                → 7A handles
                                                                  (button POSTs
                                                                   here; the
                                                                   action stashes
                                                                   intent and
                                                                   redirects to
                                                                   OmniAuth)
POST   /settings/youtube/channels                               → connect a
                                                                   channel
GET    /deletions/youtube_connection/:ids/confirm               → confirmation
                                                                   page (one or
                                                                   more channel
                                                                   ids)
DELETE /deletions/youtube_connection/:ids                       → disconnect
```

The disconnect path follows the **bulk-as-foundation** rule per `CLAUDE.md`:
single-channel disconnect is `:ids` = one id; multi-disconnect uses N. The
`Confirmable` concern is already in place from earlier phases; reuse it.

The `[ connect google account ]` button in the show page POSTs to
`/settings/youtube/connect` — that endpoint is owned by 7A but exists in this
spec's mental model as the entry point.

## Show page

Path: `/settings/youtube`.

Layout (ASCII sketch — translate to ERB faithfully against `docs/design.md`):

```
Settings → YouTube

  [ home ] [ channels ] [ videos ] [ settings ] ...
                                       └ [ general ] [ youtube ] ...

  ┌─ when no GoogleIdentity exists ────────────────────────────────────┐
  │                                                                    │
  │  No Google account connected.                                      │
  │                                                                    │
  │  [ connect google account ]   ← POSTs to /settings/youtube/connect │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘

  ┌─ when GoogleIdentity exists ───────────────────────────────────────┐
  │                                                                    │
  │  Connected as: gmrdad82@gmail.com                                  │
  │  Last authorized: 2026-05-05 14:32 UTC                             │
  │  Scopes: youtube.readonly, yt-analytics.readonly                   │
  │                                                                    │
  │  [ reconnect ]   [ disconnect google account ]                     │
  │                                                                    │
  │  ─── Your YouTube channels ───                                     │
  │                                                                    │
  │  channel id           title                  state                 │
  │  UCabc...             "Main Channel"         [ connect ]           │
  │  UCxyz...             "Side Project"         connected             │
  │                                              [ disconnect ]        │
  │  UCqwe...             "Old Channel"          [ connect ]           │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
```

When `GoogleIdentity#needs_reauth?` is true, prepend the banner partial:

```
  ┌─ banner (red text on white per design.md failure-state carve-out) ─┐
  │  Your Google grant was revoked. Pito can no longer fetch YouTube  │
  │  data for this account.                                            │
  │                                                                    │
  │  [ reconnect google account ]                                      │
  └────────────────────────────────────────────────────────────────────┘
```

The banner is **informational** in tone, not a destructive-action UI. Red is
allowed because `needs_reauth` is a **failure state**, and the docs-keeper-owned
design.md carve-out covers it (see §"Decisions (locked)" for the carve-out
reasoning). The `[ reconnect ]` button POSTs to `/settings/youtube/connect`
(same endpoint as the initial connect; the OAuth flow re-grants).

### Data fetched on show

`Settings::YoutubeController#show`:

1. `@identity = GoogleIdentity.find_by(user: Current.user)` (Beta is
   one-identity-per-user; if multiple ever exist, take the most recently
   `last_authorized_at`).
2. If `@identity` is `nil`: render the no-identity state. **Do not** call the
   YouTube API.
3. If `@identity.needs_reauth?`: render the banner state. Skip the YouTube API
   call (any call would fail anyway). List existing connected channels from the
   `channels` table only.
4. Otherwise: call
   `YouTube::Client.new(@identity).channels_list(mine: true, parts: %i[snippet statistics])`.
   Combine the response items with the tenant's existing `Channel` rows by
   matching `channel_url` → render the table.

If the `channels_list` call raises `QuotaExhaustedError` or `TransientError`,
render the page with a top-of-page red note ("YouTube API unavailable right now:
quota exceeded / network error") and fall back to listing only already-connected
`Channel` rows. Do **not** crash the page.

`PublicClient` is not used in this view.

## Connect action

`POST /settings/youtube/channels`, params: `{ youtube_channel_id: "UCabc..." }`.

Controller:

1. Verify `Current.user` and a non-`needs_reauth` `GoogleIdentity` exist.
2. Look up the channel data from the most-recent `channels_list` response.
   Re-fetch via 7B if the cached response is missing (caching strategy for this
   lookup is **don't** — call `channels_list(ids: [...], parts: ...)` directly
   with one id).
3. Build
   `channel_url = "https://www.youtube.com/channel/#{youtube_channel_id}"`.
4. `Channel.find_or_create_by!(tenant: Current.tenant, channel_url: channel_url) do |c| ... end`
   — set `oauth_identity_id` to `@identity.id`, `connected: true`. If the
   channel already existed (e.g., a seeded row, or a previously-disconnected
   channel), update `oauth_identity_id` and `connected: true` only — do not
   touch `channel_url` (the prevent_url_change guard would reject it anyway, but
   be explicit).
5. Redirect to `/settings/youtube` with a flash success "Connected '<title>'."

Boundary serialization: per `CLAUDE.md`, "yes"/"no" strings at every external
boundary. The `connected` form field, if exposed (e.g., in MCP later), uses
`"yes"`/`"no"` and converts at the boundary. For Phase 7's web form, `connected`
is set server-side; the only user-supplied parameter is `youtube_channel_id`.

## Disconnect action

Per `CLAUDE.md`'s bulk-as-foundation + `Confirmable` rules:

`GET /deletions/youtube_connection/:ids/confirm` renders
`shared/_action_screen.html.erb` with:

- Headline: "Disconnect YouTube channels?"
- Body: list each channel's title + URL.
- Footnote: "This clears the YouTube connection on these channels. Channel
  records and their data stay. If no other connected channel uses the same
  Google account, the Google grant will also be revoked."
- Confirm button: `[ confirm disconnect ]` (DELETE form to
  `/deletions/youtube_connection/:ids`).
- Cancel link: `[ cancel ]` back to `/settings/youtube`.

`DELETE /deletions/youtube_connection/:ids` invokes
`YouTube::DisconnectChannel.call(channel_ids: ids)`:

1. Load the Channel rows (tenant-scoped).
2. Snapshot
   `affected_identity_ids = channels.map(&:oauth_identity_id).compact.uniq`.
3. Update each Channel: `oauth_identity_id: nil`, `connected: false`.
4. For each `identity_id` in `affected_identity_ids`: if no remaining `Channel`
   row references it, call `Google::RevokeToken.call(identity)`.
5. After revoke: destroy the `GoogleIdentity` row. **Locked decision — destroy
   the row.** Audit trail of "this user once authorized at <timestamp>" lives in
   `youtube_api_calls`, not on the identity row; keeping the identity around
   with cleared tokens would be dead-row noise.
6. Redirect to `/settings/youtube` with flash "Disconnected N channel(s)."

`Google::RevokeToken.call(identity)`:

- POST `token=<refresh_token or access_token>` to
  `https://oauth2.googleapis.com/revoke`.
- Audit one `YoutubeApiCall` row: `endpoint: "oauth2.revoke"`,
  `http_method: "POST"`, `units: 0`, `outcome: "success"` / `"client_error"`
  based on response.
- **Locked decision — already-revoked disconnect is idempotent.** If Google
  returns "token already invalid" (the grant was revoked from
  https://myaccount.google.com/permissions before the user clicked disconnect),
  swallow the error and destroy the local row anyway. Reasoning: the local
  tokens are useless once destroyed; failing the disconnect because Google can't
  double-revoke would strand the user with a needs_reauth row they can't clear.
  Audit row records the outcome (`client_error` with `error_message` containing
  the response).

## Acceptance

- [ ] Migration adds `oauth_identity_id` and `connected` to `channels`, with the
      indexes per §"Schema delta".
- [ ] Existing seeded channels still load with `connected: false`,
      `oauth_identity_id: nil`. No data loss.
- [ ] `Channel#oauth_identity` association works; `Channel.connected` scope
      returns only connected rows.
- [ ] `/settings/youtube` renders the no-identity state when `Current.user` has
      no `GoogleIdentity`.
- [ ] `/settings/youtube` renders the connected state with a list of YouTube
      channels fetched via `YouTube::Client#channels_list`.
- [ ] `/settings/youtube` renders the `needs_reauth` banner (red text, per the
      failure-state carve-out) when `@identity.needs_reauth?` is true and **does
      not** call the YouTube API.
- [ ] On `QuotaExhaustedError` / `TransientError`, the page renders with a red
      note and a fallback channel list (just the already-connected `Channel`
      rows). No 500.
- [ ] `[ connect google account ]` POSTs to `/settings/youtube/connect`,
      bouncing through 7A's OmniAuth flow.
- [ ] Connect action: POST `/settings/youtube/channels` with a YouTube channel
      id `find_or_create_by`s a `Channel`, sets `oauth_identity_id` +
      `connected: true`, redirects with flash.
- [ ] Connect action is idempotent: posting the same channel id twice does not
      create a duplicate `Channel`.
- [ ] Connect action respects `prevent_url_change` — re-connecting an existing
      Channel does not modify `channel_url`.
- [ ] Disconnect confirmation page renders via `shared/_action_screen.html.erb`
      with the correct headline, body, and form action.
- [ ] DELETE disconnect clears `oauth_identity_id` + `connected` on the
      Channel(s) but **does not** destroy the `Channel` rows.
- [ ] Disconnect destroys the `GoogleIdentity` only when no other Channels
      reference it; if other channels do, the identity is preserved.
- [ ] Disconnect calls `Google::RevokeToken` exactly once per orphaned identity;
      one `YoutubeApiCall` row recorded per revoke.
- [ ] Disconnect against an already-revoked grant succeeds: `RevokeToken`
      swallows the "token already invalid" error, audits the failure, and the
      local `GoogleIdentity` is still destroyed.
- [ ] Bulk disconnect works: 2+ channel ids in `:ids`, all transition atomically
      (single transaction).
- [ ] No JS `alert` / `confirm` / `prompt` / `data-turbo-confirm`. The
      disconnect uses the action-confirmation page framework.
- [ ] Boolean values at external boundaries use `"yes"` / `"no"` per
      `CLAUDE.md`. (No external boundary boolean is added in Phase 7C — verify
      by code review.)
- [ ] Tenant scoping: a user under tenant A cannot connect or disconnect a
      Channel under tenant B (request spec).
- [ ] System spec drives the full happy path: visit `/settings/youtube` → click
      `[ connect ]` on a channel → see flash → click `[ disconnect ]` → confirm
      → see flash → channel back to disconnected state.
- [ ] Brakeman clean. bundler-audit clean.
- [ ] `docs/design.md` updated by the parallel docs-keeper dispatch with the
      Settings → YouTube section AND the failure-state banner carve-out note in
      the color section.

## Manual test recipe

Prereq: 7A and 7B landed and validated.

1. `bin/dev` running. Open `https://app.pitomd.com/settings/youtube`.
2. State: **no identity yet**. Page shows the empty state with
   `[ connect google account ]`. Click it. Bounces through Google consent. Lands
   back at `/settings/youtube`.
3. State: **identity present**. Page shows your Google email, last-authorized
   timestamp, scope list, and a table of your real YouTube channels (fetched via
   `channels_list(mine: true)`).
4. Click `[ connect ]` on one channel.
   - Flash: "Connected '<title>'."
   - `bin/rails console`:
     ```ruby
     Channel.connected.last.attributes.slice(
       "channel_url", "oauth_identity_id", "connected"
     )
     # => { "channel_url" => "https://www.youtube.com/channel/UC...",
     #      "oauth_identity_id" => 1, "connected" => true }
     ```
5. Visit `/channels` — the connected channel should appear in the channels index
   with the connected indicator (existing UI from Phase 3 / 4).
6. Back at `/settings/youtube`, click `[ disconnect ]` next to the connected
   channel. Confirmation page renders with the action-screen layout. Click
   `[ confirm disconnect ]`.
   - Flash: "Disconnected 1 channel(s)."
   - `Channel.find_by(channel_url: "...").attributes.slice("oauth_identity_id", "connected")`
     → `{ nil, false }`. Channel record itself still exists.
   - `GoogleIdentity.count` — if the disconnected channel was the only one
     referencing the identity, the count drops by 1; otherwise it stays the
     same.
7. Force `needs_reauth`:
   - Revoke the grant via https://myaccount.google.com/permissions.
   - Reload `/settings/youtube`. The red banner appears. The YouTube channel
     list is **not** fetched (verify via
     `YoutubeApiCall.where(created_at: 5.seconds.ago..)` — empty).
   - Click `[ reconnect google account ]`. Re-authorize. Banner clears.
8. Force a quota error:
   - `Rails.application.config.youtube_daily_budget_units = 0` in
     `bin/rails runner`.
   - Reload `/settings/youtube`. Page shows the red note "YouTube API
     unavailable right now: quota exceeded" and the fallback channel list
     (already-connected channels only).
   - Reset: `Rails.application.config.youtube_daily_budget_units = 10_000`.
9. Already-revoked disconnect path:
   - Revoke the grant via https://myaccount.google.com/permissions.
   - In `bin/rails console`, call
     `YouTube::DisconnectChannel.call(channel_ids: [Channel.connected.first.id])`.
   - The local `GoogleIdentity` is destroyed; the audit row records
     `outcome: "client_error"` for the revoke call. No exception bubbles up.
10. `bundle exec rspec spec/requests/settings/youtube_spec.rb spec/system/settings_youtube_spec.rb spec/services/youtube/disconnect_channel_spec.rb spec/services/google/revoke_token_spec.rb`
    — all green.

Teardown:

- Disconnect any test channels via the UI.
- `GoogleIdentity.destroy_all` and
  `Channel.where(connected: true).update_all(oauth_identity_id: nil, connected: false)`
  in console for a clean slate.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI (`extras/cli/`) — **skipped.** The CLI's existing `/channels` view
  will benefit from real `connected: true` data once Phase 8 syncs metadata, but
  no CLI work in Phase 7.
- MCP — **skipped.** No MCP tool surface for connect/disconnect in Phase 7.
  (Phase 8 may add `yt:write` tools that wrap `DisconnectChannel`.)
- Cloudflare Pages website — **skipped.**

## Decisions (locked)

The following decisions are confirmed and pinned. Implementation does not
re-litigate them.

- **`needs_reauth` banner color** — red (`#cc0000`), with a documented exemption
  in `docs/design.md`'s "red is destructive only" rule. Carve-out reasoning: red
  is reserved for destructive / dangerous actions AND failure states;
  `needs_reauth` is a failure state, not a decorative element. The banner
  communicates "the system is broken in a way you need to fix"; red is the right
  signal.

  **TODO-on-implementation:** the docs-keeper dispatch that lands when this spec
  ships must add a one-line note to `docs/design.md`'s color section documenting
  the failure-state carve-out (red is allowed for failure-state banners, not
  just destructive actions). This spec does NOT edit `docs/design.md` directly —
  that's the docs-keeper's lane.

Implementer notes for ergonomics (not architectural decisions, just
implementation guidance, locked at the spec level by 7A / 7B but worth restating
here):

- **Connection model** — one `GoogleIdentity` per user (locked in 7A; schema
  permits N, Beta UI enforces 1). All connected Channels share the identity.
- **Disconnect lifecycle** — destroy the `GoogleIdentity` row on full disconnect
  (last channel referencing the identity is disconnected). Historical "this user
  once authorized at <timestamp>" trail lives in `youtube_api_calls`, not on the
  identity row. Reasoning: a destroyed row is cleaner than a row with cleared
  encrypted tokens and a lingering FK.
- **Already-revoked disconnect** — idempotent. If Google's `oauth2/revoke`
  returns "token already invalid" (because the user revoked at
  myaccount.google.com first), swallow the error, audit the failure, destroy the
  local row anyway. Locking this prevents the user from being stranded with an
  unclearable `needs_reauth` row.
- **Per-channel data storage** — handled by 7B's additive `Channel` migration
  - `Video` redesign. 7C's only schema delta is `oauth_identity_id` +
    `connected` on `Channel` (the connection-state pair). Everything else lives
    in 7B.
