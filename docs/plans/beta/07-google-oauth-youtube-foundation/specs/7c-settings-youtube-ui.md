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

This is the only user-facing UI Phase 7 ships. It uses no JavaScript dialogs,
no Turbo Streams beyond what's already standard, and no decoration the design
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
- `db/migrate/<ts>_add_oauth_identity_to_channels.rb` — adds
  `oauth_identity_id` (fk to `google_identities`, nullable) and `connected`
  (boolean, not null, default `false`) to the existing `channels` table.
  Existing seeded channels stay `connected: false`,
  `oauth_identity_id: nil`.
- `app/services/youtube/disconnect_channel.rb` — disconnect logic: clear
  `oauth_identity_id` + `connected` on the Channel, conditionally revoke
  the Google grant if no other Channels reference the identity.
- `app/services/google/revoke_token.rb` — POST to
  `https://oauth2.googleapis.com/revoke`, audit (writes a
  `YoutubeApiCall` row with `client_kind: "oauth"`, `endpoint: "oauth2.revoke"`,
  `units: 0`).
- `app/views/settings/youtube/show.html.erb` — the page.
- `app/views/settings/youtube/_channel_row.html.erb` — one row per fetched
  YouTube channel.
- `app/views/settings/youtube/_needs_reauth_banner.html.erb`.
- `app/views/shared/_action_screen.html.erb` — already exists; reused for
  the disconnect confirmation page.
- `app/views/layouts/_settings_nav.html.erb` — add the Settings → YouTube
  nav entry as a `[ youtube ]` bracketed link (or whatever Phase 4 settings
  nav settled on; verify against `docs/design.md`).
- `spec/requests/settings/youtube_spec.rb`
- `spec/services/youtube/disconnect_channel_spec.rb`
- `spec/services/google/revoke_token_spec.rb`
- `spec/system/settings_youtube_spec.rb`

Documentation (parallel docs-keeper dispatch — out of this spec's lane):

- `docs/design.md` — Settings → YouTube section: bracketed table layout,
  `[ connect ]` / `[ disconnect ]` row actions, `needs reauth` banner shape.

Cross-stack scope: Rails-only.

## Schema delta

`channels` table — add two columns (new migration):

| Column                | Type    | Constraints                                        |
| --------------------- | ------- | -------------------------------------------------- |
| oauth_identity_id     | bigint  | nullable, fk → google_identities                   |
| connected             | boolean | not null, default `false`                          |

Indexes:

- `(tenant_id, oauth_identity_id)` non-unique — used by the disconnect path
  to check "is anyone else still using this identity?".
- `(tenant_id, connected)` partial where `connected = true` — fast filter
  for "all connected channels under this tenant".

`Channel` model:

- `belongs_to :oauth_identity, class_name: "GoogleIdentity", optional: true`
- `scope :connected, -> { where(connected: true) }`
- The existing `prevent_url_change` `before_update` rule (per `CLAUDE.md`)
  is unchanged. `oauth_identity_id` and `connected` are mutable.

Channel **identity / lookup** for the connect flow uses
`channel_url == "https://www.youtube.com/channel/<channel_id>"`. The connect
action builds that URL from the YouTube channel id and `find_or_create_by`
on `(tenant_id, channel_url)`. The `channel_url` lock applies only on
update; create is fine.

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
`/settings/youtube/connect` — that endpoint is owned by 7A but exists in
this spec's mental model as the entry point.

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
  ┌─ banner (red text on white per design.md destructive policy) ─────┐
  │  Your Google grant was revoked. Pito can no longer fetch YouTube  │
  │  data for this account.                                            │
  │                                                                    │
  │  [ reconnect google account ]                                      │
  └────────────────────────────────────────────────────────────────────┘
```

The banner is **informational** in tone, not a destructive-action UI —
red text is allowed because the situation itself is a failure state per
`docs/design.md` (clarify in design.md update if needed). The `[ reconnect ]`
button POSTs to `/settings/youtube/connect` (same endpoint as the initial
connect; the OAuth flow re-grants).

### Data fetched on show

`Settings::YoutubeController#show`:

1. `@identity = GoogleIdentity.find_by(user: Current.user)` (Beta is
   one-identity-per-user; if multiple ever exist, take the most recently
   `last_authorized_at`).
2. If `@identity` is `nil`: render the no-identity state. **Do not** call
   the YouTube API.
3. If `@identity.needs_reauth?`: render the banner state. Skip the YouTube
   API call (any call would fail anyway). List existing connected channels
   from the `channels` table only.
4. Otherwise: call `YouTube::Client.new(@identity).channels_list(mine: true,
   parts: %i[snippet statistics])`. Combine the response items with the
   tenant's existing `Channel` rows by matching `channel_url` → render the
   table.

If the `channels_list` call raises `QuotaExhaustedError` or `TransientError`,
render the page with a top-of-page red note ("YouTube API unavailable
right now: quota exceeded / network error") and fall back to listing only
already-connected `Channel` rows. Do **not** crash the page.

`PublicClient` is not used in this view.

## Connect action

`POST /settings/youtube/channels`, params: `{ youtube_channel_id: "UCabc..." }`.

Controller:

1. Verify `Current.user` and a non-`needs_reauth` `GoogleIdentity` exist.
2. Look up the channel data from the most-recent `channels_list` response.
   Re-fetch via 7B if the cached response is missing (caching strategy
   for this lookup is **don't** — call `channels_list(ids: [...], parts: ...)`
   directly with one id).
3. Build `channel_url = "https://www.youtube.com/channel/#{youtube_channel_id}"`.
4. `Channel.find_or_create_by!(tenant: Current.tenant, channel_url: channel_url) do |c| ... end`
   — set `oauth_identity_id` to `@identity.id`, `connected: true`. If the
   channel already existed (e.g., a seeded row, or a previously-disconnected
   channel), update `oauth_identity_id` and `connected: true` only — do not
   touch `channel_url` (the prevent_url_change guard would reject it
   anyway, but be explicit).
5. Redirect to `/settings/youtube` with a flash success "Connected
   '<title>'."

Boundary serialization: per `CLAUDE.md`, "yes"/"no" strings at every
external boundary. The `connected` form field, if exposed (e.g., in MCP
later), uses `"yes"`/`"no"` and converts at the boundary. For Phase 7's web
form, `connected` is set server-side; the only user-supplied parameter is
`youtube_channel_id`.

## Disconnect action

Per `CLAUDE.md`'s bulk-as-foundation + `Confirmable` rules:

`GET /deletions/youtube_connection/:ids/confirm` renders
`shared/_action_screen.html.erb` with:

- Headline: "Disconnect YouTube channels?"
- Body: list each channel's title + URL.
- Footnote: "This clears the YouTube connection on these channels. Channel
  records and their data stay. If no other connected channel uses the
  same Google account, the Google grant will also be revoked."
- Confirm button: `[ confirm disconnect ]` (DELETE form to
  `/deletions/youtube_connection/:ids`).
- Cancel link: `[ cancel ]` back to `/settings/youtube`.

`DELETE /deletions/youtube_connection/:ids` invokes
`YouTube::DisconnectChannel.call(channel_ids: ids)`:

1. Load the Channel rows (tenant-scoped).
2. Snapshot `affected_identity_ids = channels.map(&:oauth_identity_id).compact.uniq`.
3. Update each Channel: `oauth_identity_id: nil`, `connected: false`.
4. For each `identity_id` in `affected_identity_ids`: if no remaining
   `Channel` row references it, call `Google::RevokeToken.call(identity)`.
5. After revoke: destroy the `GoogleIdentity` row (rationale: a revoked
   grant is unusable; keeping the encrypted tokens around is a security
   hygiene loss). The user re-authorizes from scratch next time.
6. Redirect to `/settings/youtube` with flash "Disconnected N channel(s)."

`Google::RevokeToken.call(identity)`:

- POST `token=<refresh_token or access_token>` to
  `https://oauth2.googleapis.com/revoke`.
- Audit one `YoutubeApiCall` row: `endpoint: "oauth2.revoke"`,
  `http_method: "POST"`, `units: 0`, `outcome: "success"` /
  `"client_error"` based on response.
- On failure: log a warning and proceed with destroying the
  `GoogleIdentity` anyway. Google's documentation says revocation is
  best-effort; the tokens become useless once we delete them locally.

## Acceptance

- [ ] Migration adds `oauth_identity_id` and `connected` to `channels`,
      with the indexes per §"Schema delta".
- [ ] Existing seeded channels still load with `connected: false`,
      `oauth_identity_id: nil`. No data loss.
- [ ] `Channel#oauth_identity` association works; `Channel.connected`
      scope returns only connected rows.
- [ ] `/settings/youtube` renders the no-identity state when
      `Current.user` has no `GoogleIdentity`.
- [ ] `/settings/youtube` renders the connected state with a list of
      YouTube channels fetched via `YouTube::Client#channels_list`.
- [ ] `/settings/youtube` renders the `needs_reauth` banner when
      `@identity.needs_reauth?` is true and **does not** call the
      YouTube API.
- [ ] On `QuotaExhaustedError` / `TransientError`, the page renders with
      a red note and a fallback channel list (just the
      already-connected `Channel` rows). No 500.
- [ ] `[ connect google account ]` POSTs to `/settings/youtube/connect`,
      bouncing through 7A's OmniAuth flow.
- [ ] Connect action: POST `/settings/youtube/channels` with a YouTube
      channel id `find_or_create_by`s a `Channel`, sets
      `oauth_identity_id` + `connected: true`, redirects with flash.
- [ ] Connect action is idempotent: posting the same channel id twice
      does not create a duplicate `Channel`.
- [ ] Connect action respects `prevent_url_change` — re-connecting an
      existing Channel does not modify `channel_url`.
- [ ] Disconnect confirmation page renders via
      `shared/_action_screen.html.erb` with the correct headline, body,
      and form action.
- [ ] DELETE disconnect clears `oauth_identity_id` + `connected` on the
      Channel(s) but **does not** destroy the `Channel` rows.
- [ ] Disconnect destroys the `GoogleIdentity` only when no other Channels
      reference it; if other channels do, the identity is preserved.
- [ ] Disconnect calls `Google::RevokeToken` exactly once per orphaned
      identity; one `YoutubeApiCall` row recorded per revoke.
- [ ] Bulk disconnect works: 2+ channel ids in `:ids`, all transition
      atomically (single transaction).
- [ ] No JS `alert` / `confirm` / `prompt` / `data-turbo-confirm`. The
      disconnect uses the action-confirmation page framework.
- [ ] Boolean values at external boundaries use `"yes"` / `"no"` per
      `CLAUDE.md`. (No external boundary boolean is added in Phase 7C —
      verify by code review.)
- [ ] Tenant scoping: a user under tenant A cannot connect or disconnect
      a Channel under tenant B (request spec).
- [ ] System spec drives the full happy path: visit
      `/settings/youtube` → click `[ connect ]` on a channel → see flash
      → click `[ disconnect ]` → confirm → see flash → channel back to
      disconnected state.
- [ ] Brakeman clean. bundler-audit clean.
- [ ] `docs/design.md` updated by the parallel docs-keeper dispatch with
      the Settings → YouTube section.

## Manual test recipe

Prereq: 7A and 7B landed and validated.

1. `bin/dev` running. Open `https://app.pitomd.com/settings/youtube`.
2. State: **no identity yet**. Page shows the empty state with
   `[ connect google account ]`. Click it. Bounces through Google consent.
   Lands back at `/settings/youtube`.
3. State: **identity present**. Page shows your Google email,
   last-authorized timestamp, scope list, and a table of your real
   YouTube channels (fetched via `channels_list(mine: true)`).
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
5. Visit `/channels` — the connected channel should appear in the
   channels index with the connected indicator (existing UI from
   Phase 3 / 4).
6. Back at `/settings/youtube`, click `[ disconnect ]` next to the
   connected channel. Confirmation page renders with the action-screen
   layout. Click `[ confirm disconnect ]`.
   - Flash: "Disconnected 1 channel(s)."
   - `Channel.find_by(channel_url: "...").attributes.slice("oauth_identity_id", "connected")`
     → `{ nil, false }`. Channel record itself still exists.
   - `GoogleIdentity.count` — if the disconnected channel was the only
     one referencing the identity, the count drops by 1; otherwise it
     stays the same.
7. Force `needs_reauth`:
   - Revoke the grant via https://myaccount.google.com/permissions.
   - Reload `/settings/youtube`. The red banner appears. The YouTube
     channel list is **not** fetched (verify via
     `YoutubeApiCall.where(created_at: 5.seconds.ago..)` — empty).
   - Click `[ reconnect google account ]`. Re-authorize. Banner clears.
8. Force a quota error:
   - `Rails.application.config.youtube_daily_budget_units = 0` in
     `bin/rails runner`.
   - Reload `/settings/youtube`. Page shows the red note "YouTube API
     unavailable right now: quota exceeded" and the fallback channel
     list (already-connected channels only).
   - Reset:
     `Rails.application.config.youtube_daily_budget_units = 10_000`.
9. `bundle exec rspec spec/requests/settings/youtube_spec.rb
   spec/system/settings_youtube_spec.rb spec/services/youtube/disconnect_channel_spec.rb
   spec/services/google/revoke_token_spec.rb` — all green.

Teardown:
- Disconnect any test channels via the UI.
- `GoogleIdentity.destroy_all` and `Channel.where(connected: true).update_all(oauth_identity_id: nil, connected: false)`
  in console for a clean slate.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI (`extras/cli/`) — **skipped.** The CLI's existing
  `/channels` view will benefit from real `connected: true` data once
  Phase 8 syncs metadata, but no CLI work in Phase 7.
- MCP — **skipped.** No MCP tool surface for connect/disconnect in
  Phase 7. (Phase 8 may add `yt:write` tools that wrap `DisconnectChannel`.)
- Cloudflare Pages website — **skipped.**

## Open questions

1. **Connection model: single `GoogleIdentity` per User, or one per
   channel?** This spec assumes **one identity per user** (Beta UI
   enforces it, schema allows N). All connected Channels share the same
   identity. This matches the plan. Confirm with the master agent that
   "one identity, N channels" is the desired model — alternatives:
   - "One identity per channel" (more granular revocation, more
     consent friction).
   - "Multiple identities per user" (Theta concern).
   Default: one per user.
2. **Banner color.** This spec uses red text (`#cc0000`) on the
   `needs_reauth` banner. `docs/design.md` reserves red for destructive
   actions only. The banner describes a **failure state**, not a
   destructive action — strictly speaking it might violate the rule.
   Alternatives: keep the banner in the muted gray (`#555`) with no
   color, or carve out a "failure state" exemption in `docs/design.md`.
   The docs-keeper dispatch should decide; this spec defaults to red and
   asks for the design exemption.
3. **Destroy `GoogleIdentity` on full disconnect, or just clear
   tokens?** This spec destroys. Alternative: keep the row, null out
   the encrypted token columns, set `needs_reauth: true`. Destroying
   loses the historical "this user once authorized at <timestamp>"
   trail; clearing keeps it but leaves dead rows. Default: destroy.
4. **Storage of YouTube channel/video IDs.** This spec stores them on
   the existing `Channel` table via `channel_url`. The plan's
   `oauth_identity_id` addition to `channels` is the entire schema
   change for connection state. Phase 8 will add separate tables
   (videos, stats); they belong to a Channel, not to a GoogleIdentity.
   Confirm this layering is correct.
5. **Disconnect during `needs_reauth` state.** If the grant is already
   revoked on Google's side, calling `oauth2/revoke` will return an
   error. This spec's `RevokeToken.call` swallows the error and still
   destroys the identity locally. Confirm this is the right policy
   (alternative: skip the revoke call entirely when `needs_reauth?`
   is true).
