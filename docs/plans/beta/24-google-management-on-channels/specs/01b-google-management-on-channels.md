# 24b — Google management UI on `/channels` (banner + per-channel inline panel)

## Goal

Move Google / YouTube OAuth connection management from `/settings/youtube` to
`/channels`. The new surface has two parts:

1. **Top-of-index banner** on `/channels` — connected-accounts summary, plus a
   `[+ add another Google account]` button.
2. **Per-channel inline Google panel** on `/channels/:slug` — the connection
   that owns this specific channel (email, scopes, last-authorized timestamp,
   reauth state).

Per the user note and the architect's autonomous decision: banner on index +
details inline on show. The Settings page is for app-wide preferences; channel-
shaped state belongs on `/channels`.

This sub-spec does not implement the `[revoke]` button — that surface is the job
of sub-spec 24c. It only renders the Google UI.

## Files touched

### Views (new)

- `app/views/channels/_google_banner.html.erb` — NEW partial rendered at the top
  of `/channels` index. Renders:
  - When zero connections exist: empty state + `[connect google]` link.
  - When ≥ 1 connection exists: one row per connection with `<email>` —
    `<N channels>` — `<last-authorized timestamp>`, followed by a
    `[+ add another Google account]` link.
  - Reauth state: if any connection has `needs_reauth: true`, the banner row
    renders a `[reauthorize]` link with the appropriate muted styling.
- `app/views/channels/_google_panel.html.erb` — NEW partial rendered on the
  channel show page (`/channels/:slug`). Renders:
  - When the channel has a `youtube_connection_id`: the connection's email,
    scopes (space-separated), `last_authorized_at`, `needs_reauth?` state.
  - When the channel has no connection (`youtube_connection_id IS NULL`): a "no
    Google connection" line + `[connect this channel]` link. (Defer: if
    connecting an existing channel to a Google grant is not yet a supported
    flow, the link points to the same OmniAuth entry point the banner uses, and
    the OAuth callback's channel-discovery logic picks it up. Confirm the
    callback's matching logic.)

### Views (updated)

- `app/views/channels/index.html.erb` — render `_google_banner` at the top of
  the page, above the existing channels list and bulk-mode shell.
- `app/views/channels/show.html.erb` — render `_google_panel` as a dedicated
  pane in the show page layout. Placement: after the existing channel-info pane,
  before the videos / change-log / diff panes (or as a new pane in the workspace
  shell — confirm the existing pane convention).

### Controllers

- `app/controllers/channels_controller.rb`:
  - In `#index`: load `@youtube_connections` (current user's connections ordered
    by `last_authorized_at: :desc`) and any aggregate counts the banner partial
    needs.
  - In `#show`: expose `@youtube_connection` (i.e.
    `@channel.youtube_connection`).
  - Add `#connect` action (or reuse the existing
    `Settings::YoutubeController#connect` body — see Files moved below). URL:
    `POST /channels/connect_google`. Body delegates to the OmniAuth dance with
    `prompt=select_account` for `account=new`.
  - Include the existing `YoutubeConnectionOauthRedirect` concern so the
    callback can route back to `/channels`.

### Controllers (moved)

- The body of `Settings::YoutubeController#connect` moves into
  `ChannelsController#connect_google`. The intent-stash logic in the
  `YoutubeConnectionOauthRedirect` concern is updated so its post-OAuth redirect
  target is `/channels` (was `/settings/youtube`). Verify the concern's
  redirect-target code does not hardcode the old path.

### Routes

- `config/routes.rb`:
  - Add `post "/channels/connect_google" → channels#connect_google`.
  - Verify the OmniAuth callback handler routes back to `/channels` (the intent
    stash from the concern carries the routing).

### Specs

- `spec/views/channels/_google_banner.html.erb_spec.rb` — NEW. Covers:
  - Zero-connections empty state renders `[connect google]`.
  - One connection renders the row + `[+ add another Google account]`.
  - Multiple connections render one row each, ordered by
    `last_authorized_at: :desc`.
  - `needs_reauth: true` connection renders `[reauthorize]`.
- `spec/views/channels/_google_panel.html.erb_spec.rb` — NEW. Covers:
  - With connection: renders email + scopes + last-authorized + reauth state.
  - Without connection: renders the "no connection" line + connect link.
- `spec/requests/channels_spec.rb` (existing) — extend:
  - `GET /channels` includes the banner partial (smoke-assert a banner-class
    selector or a stable string from the empty state).
  - `GET /channels/:slug` includes the google_panel partial.
  - `POST /channels/connect_google` triggers the OmniAuth redirect chain.
- Existing OmniAuth callback specs — verify they still pass after the redirect
  target changes from `/settings/youtube` to `/channels`. Update assertions if
  needed.

## Acceptance

- [ ] `GET /channels` renders the Google banner at the top of the page.
- [ ] When the user has zero YoutubeConnection rows, the banner renders the
      empty state with a `[connect google]` link to the OmniAuth entry point.
- [ ] When the user has ≥1 connections, the banner renders one row per
      connection (email, channel count, last-authorized timestamp) plus a
      `[+ add another Google account]` link.
- [ ] When any connection has `needs_reauth: true`, the banner row renders a
      `[reauthorize]` link with the appropriate styling.
- [ ] `GET /channels/:slug` renders the Google panel showing the connection that
      owns the channel (email, scopes, last-authorized, reauth state).
- [ ] `POST /channels/connect_google?account=new` redirects to
      `/auth/google_oauth2?prompt=select_account+consent&include_granted_scopes=true`.
- [ ] `POST /channels/connect_google` without `account=new` redirects to
      `/auth/google_oauth2`.
- [ ] The OmniAuth callback returns the user to `/channels` (not
      `/settings/youtube`).
- [ ] Component / partial specs cover empty + populated + reauth-needed states.
- [ ] Bracketed-link convention: `[connect google]`,
      `[+ add another Google     account]`, `[reauthorize]` (no inner padding —
      per project rule A).
- [ ] Full RSpec suite green; design alignment with `docs/design.md` if any new
      style was introduced.

## Manual test recipe

1. `bin/dev`.
2. Visit `http://127.0.0.1:3027/channels`. Expect: a banner at the top of the
   page shows the connected Google account(s) with a
   `[+ add another Google account]` link.
3. If you have zero connections (fresh DB): the banner shows the empty state
   with `[connect google]`. Click it; expect the Google account picker.
4. Click a channel row to open `/channels/:slug`. Expect: a Google panel renders
   inline showing the connection's email + scopes + last-authorized.
5. If you have a connection with `needs_reauth: true` (toggle it in the Rails
   console: `YoutubeConnection.first.update!(needs_reauth: true)`), reload
   `/channels`. Expect: the banner row shows `[reauthorize]`.
6. Click `[+ add another Google account]`. Expect: Google's account picker
   renders (because `prompt=select_account` is passed). After completing OAuth,
   expect to land back on `/channels` (not `/settings/youtube`).

Teardown: revert `needs_reauth` toggle:
`YoutubeConnection.first.update!(needs_reauth: false)`.

## Cross-stack scope

- **Rails web:** in scope.
- **MCP:** not in scope. No new tool is added; the existing
  `list_youtube_connections` / `oauth_status` MCP tool (if any) reads from the
  same model and is unaffected.
- **CLI:** not in scope. The CLI does not render Google account management; it
  only reads channels and videos via JSON endpoints. The channels-list JSON
  shape is unchanged.
- **Website:** not in scope.

## Open questions

1. Banner placement: above the saved-views row, OR between the page heading and
   the saved-views row? Architect recommendation: between the heading and
   saved-views — the banner is page-level state, not list-state.
2. Per-channel panel placement on show page: dedicated pane in the pane shell
   (matches the existing `.pane` primitive), OR a plain block above the panes?
   Architect recommendation: dedicated pane. Reuse `.pane--standalone` if it
   needs full-width.
3. Should the `[connect this channel]` link from the show-page panel (when
   `channel.youtube_connection_id IS NULL`) reuse the same OmniAuth flow as the
   banner's `[+ add another Google account]`, or a dedicated flow that
   pre-targets this channel's UC-id? Architect recommendation: reuse the same
   flow — the OAuth callback's channel-discovery logic finds the matching
   channel by UC-id. Confirm the callback handles this gracefully.
4. The OmniAuth intent stash currently carries `return_to=/settings/youtube`.
   Migrating it to `/channels` requires touching
   `YoutubeConnectionOauthRedirect`. Is there any other surface (e.g. the
   needs-reauth banner from `_needs_reauth_banner.html.erb`) that depends on the
   old return target? Surface in the dispatch.
