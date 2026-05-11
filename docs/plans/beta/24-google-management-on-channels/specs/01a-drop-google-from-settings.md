# 24a — Drop Google section from `/settings` + remove `/settings/youtube`

## Goal

Remove every Google / YouTube OAuth surface from `/settings`. Settings goes back
to its lane — app-wide preferences only. The Google card on the Settings index
disappears. The dedicated `/settings/youtube` page is deleted. The controller,
view, and route all go. A 301 redirect from `/settings/youtube` → `/channels` is
added in `config/routes.rb` for browser-bookmark back-compat.

After this sub-spec lands, the channel-shaped state that used to live on
Settings moves to `/channels` (covered by sub-spec 24b).

## Files touched

- `app/controllers/settings_controller.rb` — remove Google-related ivars from
  `#index`: `@youtube_connections`, `@youtube_connection`, `@channel_labels`,
  `@channels_count`. Drop the `:youtube_oauth` branch from `#update`. The
  `OAUTH_KEYS` constant (`youtube_client_id`, `youtube_client_secret`,
  `youtube_redirect_uri`) is dropped — those credentials live in Rails
  credentials per `CLAUDE.md` configuration strategy, not in AppSetting. The
  `update_oauth` private method goes with them.
- `app/views/settings/index.html.erb` — remove the "Google" fieldset entirely.
  Verify no neighboring fieldset (workspaces, appearance, voyage, search,
  tokens, sessions, oauth applications) leaks blank space.
- `app/controllers/settings/youtube_controller.rb` — DELETE the file.
- `app/views/settings/youtube/show.html.erb` — DELETE the file (and any partials
  it owns, e.g. `_needs_reauth_banner.html.erb`, `_connection_row.html.erb` if
  those partials are not referenced elsewhere — audit before deleting).
- `app/controllers/concerns/youtube_connection_oauth_redirect.rb` — KEEP. The
  concern is reused by the new `/channels`-side connect flow in sub-spec 24b.
- `app/controllers/youtube_connections/oauth_callbacks_controller.rb` — KEEP.
  The OAuth callback survives untouched; only the entry-point page moves.
- `config/routes.rb`:
  - Remove `get "/settings/youtube" → settings/youtube#show"` and
    `post "/settings/youtube/connect" → settings/youtube#connect`.
  - Add `get "/settings/youtube", to: redirect("/channels", status: 301)` —
    one-phase back-compat redirect.
  - The OmniAuth `/auth/google_oauth2/callback` route is unchanged.
- `app/views/shared/_navigation.html.erb` (or equivalent layout) — audit and
  remove any `[settings/youtube]` link.
- `app/components/keyboard_shortcuts_modal_component.html.erb` — audit for any
  key bound to a `/settings/youtube` URL; rebind to `/channels` if so.
- Any `link_to settings_youtube_path` callsite anywhere in `app/` —
  `grep -rn "settings_youtube" app/` and migrate each to `channels_path`
  (covered by sub-spec 24b for the Connect button; here, only the link removals
  are in scope).
- `spec/requests/settings_spec.rb` — remove specs that exercise the
  `:youtube_oauth` update branch and the Google card render path.
- `spec/requests/settings/youtube_spec.rb` — DELETE the file.
- `spec/views/settings/index.html.erb_spec.rb` — if exists, remove Google
  fieldset render assertions; otherwise no-op.
- `spec/system/settings_youtube_*_spec.rb` — DELETE files matching the pattern.
- `config/locales/en.yml` — drop any `settings.youtube.*` keys; audit references
  first.

## Acceptance

- [ ] `GET /settings` returns 200 with no Google fieldset. The page renders
      workspaces / appearance / voyage / search / tokens / sessions / oauth
      applications fieldsets only.
- [ ] `GET /settings/youtube` returns `301 Moved Permanently` with a
      `Location: /channels` header.
- [ ] `PATCH /settings` with `section=youtube_oauth` returns 404 (route gone) OR
      routes through the legacy fallback and is rejected — confirm the exact
      behavior in the controller spec.
- [ ] `app/controllers/settings/youtube_controller.rb` and
      `app/views/settings/youtube/show.html.erb` are absent from the tree.
- [ ] `grep -rn "settings_youtube" app/ config/ spec/` returns zero matches
      (post-sweep verification — except the routes.rb redirect line).
- [ ] No link in the navigation / layout / keyboard-shortcuts modal still points
      to `/settings/youtube`.
- [ ] `SettingsController#index` no longer references `@youtube_connections` /
      `@youtube_connection` / `@channel_labels`.
- [ ] Full RSpec suite green; Brakeman + bundler-audit clean.
- [ ] Request specs cover: - `GET /settings` happy path (200, no Google fieldset
      in rendered body). - `GET /settings/youtube` returns 301 with the right
      Location. - Existing settings update branches (workspaces, appearance,
      voyage) still pass.

## Manual test recipe

1. `bin/dev`.
2. Visit `http://127.0.0.1:3027/settings`. Expect: the page renders without a
   Google fieldset. No "Connected accounts", no `[connect google]`, no channel
   list, no client-id / client-secret inputs.
3. Visit `http://127.0.0.1:3027/settings/youtube`. Expect: the browser address
   bar updates to `/channels` (301 redirect), and the channels page renders.
4. Open DevTools → Network. Re-visit `/settings/youtube`. Confirm the first
   response is `301` with `Location: /channels`.
5. View the navigation HTML. Confirm no link target ends in `/settings/youtube`.

Teardown: no DB state changes; nothing to reset.

## Cross-stack scope

- **Rails web:** in scope.
- **MCP:** not in scope. The MCP tools never had a `/settings/youtube` surface
  (they speak to the database directly).
- **CLI:** not in scope. The CLI's settings panes were already aligned with the
  Rails index (no per-CLI YouTube settings pane). Verify
  `extras/cli/src/ui/settings.rs` does not reach for a "Google" pane — if it
  does, raise as an open question.
- **Website:** not in scope.

## Open questions

1. Confirm the 301-redirect retention policy: keep the redirect for one phase,
   then drop in a hygiene sweep? OR keep indefinitely as quiet back-compat?
2. The `OAUTH_KEYS` constant in `SettingsController` references
   `youtube_client_id` / `youtube_client_secret` / `youtube_redirect_uri`,
   stored in AppSetting. Per `CLAUDE.md` configuration strategy, these belong in
   Rails credentials. Is this sub-spec the right place to migrate them, or
   should that be its own follow-up under `docs/orchestration/follow-ups.md`?
   Architect recommendation: SEPARATE follow-up — this phase removes the UI, not
   the underlying storage location. The follow-up file logs the migration so a
   later hygiene pass picks it up.
3. Audit reveals partial templates owned by `Settings::YoutubeController` (e.g.
   `_needs_reauth_banner.html.erb`). If any partial is also referenced from
   elsewhere (`settings/index.html.erb` Google fieldset, the channels page) it
   cannot be deleted in this sub-spec — it must be moved to
   `app/views/channels/` first (sub-spec 24b). Surface the dependency map in the
   dispatch.
