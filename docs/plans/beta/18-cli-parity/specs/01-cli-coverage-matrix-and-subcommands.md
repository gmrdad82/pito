# Phase 18 — CLI Parity Matrix & Subcommands

> **Meta-spec.** This consolidates the CLI surface across every realignment
> work unit that has (or will have) a Rails web spec. It does NOT introduce new
> functionality; it enumerates which web actions get a `pito` CLI subcommand,
> what those subcommands look like, and which actions stay web-exclusive.
>
> Source of truth: web. CLI is best-effort parity. Per
> `docs/realignment-2026-05-09.md` work unit 10 + Resolved ambiguities 2/3.

## Goal

Lock the per-domain CLI coverage matrix that downstream `cli-impl` agents
execute against, one domain at a time, as each domain's Rails surface lands.
The matrix is the contract: every web action either gets an enumerated
`pito <noun> <verb>` subcommand, or is explicitly marked web-exclusive with a
rationale. The TUI keeps its current shape (channels, videos, footage,
projects, dashboard); subcommands carry the new domains (calendar,
notifications, games, bundles, plus channel/video edit + publish).

The spec also locks the cross-cutting plumbing — auth file path, output
formats, error / exit-code translation, naming conventions, test posture — so
each per-domain dispatch reuses the same skeleton and the binary stays
internally consistent.

This is a **planning artifact**. No code lands from this spec directly. Each
domain row in the matrix below feeds a separate `architect-spec` dispatch (or
piggybacks on the per-domain Rails spec) which the `cli-impl` agent then
implements. This spec exists so the master agent has a single document to
diff against when verifying CLI parity at the end of each work unit.

## Files touched

This spec writes documentation only:

- `docs/plans/beta/18-cli-parity/specs/01-cli-coverage-matrix-and-subcommands.md`
  (this file).
- `docs/plans/beta/18-cli-parity/log.md` (stub created alongside).

Downstream implementation (NOT this spec's scope) lands across:

- `extras/cli/src/cli.rs` — clap subcommand tree expanded per the matrix below.
- `extras/cli/src/commands/<noun>.rs` — one module per noun (`channels.rs`,
  `videos.rs`, `calendar.rs`, `notifications.rs`, `games.rs`, `bundles.rs`,
  `auth.rs`, `tokens.rs`).
- `extras/cli/src/api/http_client.rs` — gains an `Authorization: Bearer <token>`
  header sourced from `auth.toml`.
- `extras/cli/src/auth.rs` (new) — reads `~/.config/pito/auth.toml`, exposes
  `current_token() -> Result<String>`.
- `extras/cli/src/output.rs` (new) — JSON / plaintext renderers, TTY detection,
  exit-code translation.
- `extras/cli/src/commands/<noun>_test.rs` — per-subcommand unit tests.
- `extras/cli/tests/integration_*.rs` — end-to-end tests against `wiremock`.
- `extras/cli/README.md` — if present, updated with subcommand index. (If
  absent, downstream creates it.)
- `docs/architecture.md` — CLI section updated by the docs-keeper at the close
  of each domain dispatch.

## Coverage matrix (every web action enumerated)

The matrix groups by realignment work unit (== docs/plans/beta/<NN-phase>/
folder) so each row maps to a future per-domain `cli-impl` dispatch.

Conventions used in the table:

- **Web action** — the user-visible HTML controller verb.
- **HTTP** — Rails route(s) the controller exposes. JSON variants
  (`Accept: application/json` / `.json`) are the CLI's actual target.
- **CLI subcommand** — verb-first within a noun group: `pito <noun> <verb>`.
  Naming follows the **Subcommand naming conventions** section below.
- **MCP** — yes / no — whether the same action lands as an MCP tool. Logged
  here for cross-surface traceability; binding decisions live in each MCP
  spec, not here.
- **Notes** — flags, confirmation requirements, output format, web-only
  rationale.

Where a web action is web-exclusive, the **CLI subcommand** column reads
`(web-only)` with the rationale in **Notes**.

### Work unit 1 — Tenant drop (phase folder `08-tenant-drop/`)

Schema-only refactor. No new web actions. CLI updates:

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| n/a | n/a | (cleanup only) | n/a | `extras/cli/src/api/client.rs` Channel struct drops `tenant_id` field; Mock fixtures regenerate. No new subcommand surface. |

### Work unit 2 — MCP scope simplification (phase folder `09-mcp-scope-simplification/`)

Affects token minting + scope picker. CLI updates:

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List API tokens | `GET /settings/tokens` | `pito tokens list` | no | yields a table. `--json` for scriptable. |
| Mint API token | `POST /settings/tokens` | `pito tokens create --name <name> --scope <dev\|app>` | no | scopes accepted: `dev`, `app`, or both. Prints the secret once; copy-paste guidance in stderr. `--json` returns `{ id, name, scopes, secret }`. |
| Revoke API token | `DELETE /settings/tokens/:id` (action confirmation page) | `pito tokens revoke <id> --confirm` | no | `--confirm yes` required (per **Yes / no for external booleans** rule). Without `--confirm yes`, prints the action confirmation preview and exits 0. |
| Show current token info | `GET /settings/tokens/current` (n/a, derived) | `pito auth whoami` | no | reads `~/.config/pito/auth.toml`, calls `GET /api/auth/whoami.json`, prints `user_id`, `email`, `scopes`. |
| Configure token locally | n/a (manual `~/.config/pito/auth.toml` edit) | `pito auth login` | no | interactive wizard: prompts for base URL + token, writes `auth.toml`. v1 alternative is hand-editing the file; the wizard is convenience. |
| Logout | n/a (delete `auth.toml`) | `pito auth logout` | no | deletes `~/.config/pito/auth.toml` after a `--confirm yes`. |

### Work unit 3 — Channel data sync + edit surface (phase folder `10-channel-data-sync/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List channels | `GET /channels` | `pito channels list` | yes | `--limit 50` default; `--json` available; plaintext uses fixed columns id, url, title, subs, last\_synced\_at. |
| Show channel | `GET /channels/:id` | `pito channels show <id>` | yes | `--json` available; plaintext is two-column key/value layout. |
| Create channel | `POST /channels` | `pito channels add <url>` | yes | URL is locked after create per CLAUDE.md Architecture notes. |
| Star / unstar | `PATCH /channels/:id` | `pito channels star <id> [--unstar]` | yes | thin shortcut; `--star yes` / `--star no` accepted as alternative form. |
| Edit channel metadata | `PATCH /channels/:id` (writable subset: title, description, country) | `pito channels edit <id>` | yes | interactive: prompts for each writable field, defaults to current value. `--field=value` for non-interactive (e.g., `--title "..."`). `--json` returns the updated record. |
| Sync channel | `POST /syncs/channel/:ids` | `pito channels sync <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation per CLAUDE.md hard rule. Without `--confirm yes`, prints preview JSON and exits 0. |
| Delete channel | `POST /deletions/channel/:ids` | `pito channels delete <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation. Same preview-without-confirm behavior. |
| Banner / avatar / watermark preview | image rendering on `/channels/:id` | (web-only) | no | Visual preview only. CLI prints URLs via `pito channels show`; rendering is the web's job. |
| Disconnect YouTube identity | `DELETE /settings/google_identity` | (web-only) | no | OAuth identity teardown. Sensitive UX; web-only. |

### Work unit 4 — Video schema expansion + edit surface + pre-publish checklist (phase folder `11-video-workflow-features/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List videos | `GET /videos` | `pito videos list` | yes | `--channel <id>` filter; `--limit 50` default; `--privacy public\|unlisted\|private` filter; `--json`. |
| Show video | `GET /videos/:id` | `pito videos show <id>` | yes | `--json`; plaintext key/value. |
| Edit video metadata | `PATCH /videos/:id` (writable subset: title, description, tags, category, thumbnail, privacy, publishAt, made-for-kids, contains-synthetic-media) | `pito videos edit <id>` | yes | interactive prompts per field, defaults to current. Non-interactive flags: `--title`, `--description`, `--tags=a,b,c`, `--category-id`, `--privacy private\|unlisted\|public`, `--publish-at <iso8601>`, `--made-for-kids yes\|no`, `--contains-synthetic-media yes\|no`. CLI must implement read-modify-write semantics — fetch current state first, merge, PATCH. Note 1's destructive-PUT-per-part gotcha is the load-bearing test obligation. |
| Star / unstar video | `PATCH /videos/:id` | `pito videos star <id> [--unstar]` | yes | mirrors `channels star`. |
| Sync video | `POST /syncs/video/:ids` | `pito videos sync <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation. |
| Delete video | `POST /deletions/video/:ids` | `pito videos delete <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation. |
| Publish (publish-state transition) | `POST /videos/:id/publish` (or `PATCH` with privacy + checklist payload) | `pito videos publish <id> --confirm yes` | yes | requires `--confirm yes` AND a checklist confirmation. Printed flow: 1) fetch video, 2) print four-item checklist (game / age / paid promotion / end screen), 3) prompt user to acknowledge each (`--ack-game yes`, `--ack-age yes`, `--ack-paid-promotion yes`, `--ack-end-screen yes` for non-interactive use; all four required), 4) PATCH privacy. The web's pre-publish modal maps to these acks 1:1. |
| Schedule publish | `POST /videos/:id/publish` with `publish_at` | `pito videos schedule <id> --at <iso8601> --confirm yes` | yes | same checklist obligation as `publish`. Privacy defaults to `private` until `publish_at`. |
| Unpublish (public → private/unlisted) | `PATCH /videos/:id` privacy change | `pito videos unpublish <id> --confirm yes` | yes | per realignment Resolved ambiguity 7, the checklist DOES NOT apply. `--confirm yes` is the single gate. |
| Upload new video file | `POST /videos` (multipart upload) | (web-only) | no | per realignment work unit 10 example: file upload heavy. Web-only by design. |
| Pre-publish Studio deep-link buttons | UI links on video edit page | (web-only) | no | UI affordance only. |
| Project association change | `PATCH /videos/:id` (`project_id`) | `pito videos assign-project <id> [--project <project_id>] [--clear]` | yes | direct nullable column per Resolved ambiguity 1. `--clear` sets to NULL. |

### Work unit 5 — Analytics sync engine + tables + dashboard (phase folder `13-app-stats-observability/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| Channel analytics summary | `GET /channels/:id/analytics` | `pito channels analytics <id> [--window 7d\|28d\|90d\|365d\|lifetime]` | yes | windowed-summary surfacing. `--json` for the full summary; plaintext shows the headline ratios. |
| Video analytics summary | `GET /videos/:id/analytics` | `pito videos analytics <id> [--window ...]` | yes | mirrors channel analytics. |
| Top videos in window | `GET /channels/:id/top_videos` | `pito channels top-videos <id> [--window 28d] [--limit 10]` | yes | uses `top_videos_window` table. |
| Retention curve | `GET /videos/:id/retention` | `pito videos retention <id>` | yes | `--json` returns the curve as `[{second: int, retention: float}, ...]`. Plaintext renders an ASCII sparkline (TTY only); pipe / non-TTY falls back to the JSON-style array. |
| Dashboard charts (Studio-faithful) | `GET /` (dashboard) | `pito dashboard` | no | TUI-only headline dashboard already exists; subcommand surface uses `pito channels analytics` + `pito videos analytics` instead. |
| Trigger analytics sync (manual override) | `POST /admin/analytics/sync` (operator-only) | `pito analytics sync --confirm yes` | yes | rare operator action; gated by `--confirm yes`. |
| Cross-video locals (when-to-publish, best-duration, topics-that-work, thumbnail-decay) | `GET /channels/:id/insights` | `pito channels insights <id>` | yes | reads the locally-joined cross-video computation tables. |

### Work unit 6 — Game model expansion + IGDB sync (phase folder `12-game-model-igdb/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List games (Steam shelf) | `GET /games` | `pito games list [--shelf <id>] [--limit 50]` | yes | `--json` returns full records; plaintext is fixed-column. |
| Show game | `GET /games/:id` | `pito games show <id>` | yes | `--json` available. |
| Add game (manual entry) | `POST /games` | `pito games add --title "..." [--platform <name>]` | yes | for ad-hoc local entries. |
| Sync from IGDB | `POST /games/:id/sync` | `pito games sync <id> --confirm yes` | yes | last-write-wins semantics; the CLI prints which fields were overwritten. |
| Sync by IGDB id (bulk import) | `POST /games/sync_by_igdb` | `pito games import --igdb-id <id>[,<id>...] --confirm yes` | yes | bulk import flow per realignment "if a `pito sync ...` subcommand emerges naturally". |
| Edit local-only fields | `PATCH /games/:id` (writable: `platform_owned`, `played_at`, `notes`, `hours_of_footage_manual`) | `pito games edit <id>` | yes | only the local-only subset; IGDB-sourced fields are read-only here. |
| Delete game | `POST /deletions/game/:ids` | `pito games delete <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation. |
| List bundles | `GET /bundles` | `pito bundles list` | yes | `--type series\|collection\|genre\|custom` filter. |
| Show bundle | `GET /bundles/:id` | `pito bundles show <id>` | yes | shows members, composite cover URL. |
| Create bundle | `POST /bundles` | `pito bundles create --name "..." --type custom` | yes | |
| Add member | `POST /bundles/:id/members` | `pito bundles add-member <bundle_id> --game <game_id>` | yes | |
| Remove member | `DELETE /bundles/:id/members/:game_id` (action confirmation page) | `pito bundles remove-member <bundle_id> --game <game_id> --confirm yes` | yes | |
| Regenerate composite cover | `POST /bundles/:id/regenerate_cover` | `pito bundles regenerate-cover <bundle_id> --confirm yes` | yes | rare — usually auto-fires on member-list change. |
| Composite cover image render | Active Storage variant URL | (web-only) | no | image bytes; CLI prints the URL via `pito bundles show`. |
| Steam-shelf listing UX | `GET /games` (visual layout) | (web-only) | no | shelf rendering is a web concern. CLI offers flat `pito games list`. |

### Work unit 7 — Calendar surface (phase folder `14-calendar/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List entries (default view: month) | `GET /calendar` | `pito calendar list [--from <date>] [--to <date>] [--type <type>] [--limit 50]` | yes | `--type` filters by `entry_type` (`channel_published`, `video_published`, `video_scheduled`, `game_release`, `purchase_planned`, `milestone_manual`, `milestone_auto`, `custom`). `--json` available. |
| Upcoming view | `GET /calendar/upcoming` | `pito calendar upcoming [--days 30]` | yes | shortcut for `--from today --to today+N`. |
| Show entry | `GET /calendar/:id` | `pito calendar show <id>` | yes | |
| Create manual entry | `POST /calendar` | `pito calendar add --type <type> --title "..." --on <iso8601> [--precision day\|week\|month\|quarter\|year]` | yes | derived entries cannot be created via this endpoint. |
| Edit entry | `PATCH /calendar/:id` | `pito calendar edit <id>` | yes | interactive prompts; manual-only fields editable. |
| Delete entry | `POST /deletions/calendar_entry/:ids` | `pito calendar delete <id>[,<id>...] --confirm yes` | yes | bulk-as-foundation. |
| Mark purchase planned | `POST /calendar/:game_release_id/purchases` | `pito calendar mark-purchase <game_release_id> [--storefront steam\|gog\|...]` | yes | links a `purchase_planned` to a `game_release`. |
| Cancel purchase plan | `DELETE /calendar/purchases/:id` (action confirmation page) | `pito calendar cancel-purchase <id> --confirm yes` | yes | |
| List milestone rules | `GET /calendar/milestone_rules` | `pito calendar milestone-rules list` | yes | |
| Create milestone rule | `POST /calendar/milestone_rules` | `pito calendar milestone-rules create --kind <kind> --threshold <n>` | yes | |
| Disable milestone rule | `PATCH /calendar/milestone_rules/:id` | `pito calendar milestone-rules disable <id> --confirm yes` | yes | |
| Month grid / Schedule view rendering | `GET /calendar?view=month` etc. | (web-only) | no | per Resolved ambiguity 5, month grid + Schedule view are the locked UI shapes. CLI surfaces the underlying entries via `pito calendar list`. |

### Work unit 8 — Notification model + delivery channels + formatter + webhook delivery (phase folder `15-notifications/`)

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List notifications (in-app inbox) | `GET /notifications` | `pito notifications list [--unread] [--severity normal\|urgent] [--limit 50]` | yes | per Resolved ambiguity 6, all-users-see-all. `--json` available. |
| Show notification | `GET /notifications/:id` | `pito notifications show <id>` | yes | full payload + formatter preview. |
| Mark read | `PATCH /notifications/:id` | `pito notifications mark-read <id>[,<id>...]` | yes | bulk-as-foundation; no `--confirm` required (idempotent). |
| Mark all read | `POST /notifications/mark_all_read` | `pito notifications mark-all-read --confirm yes` | yes | confirmation gate for the irreversible-feeling action. |
| List delivery channels | `GET /settings/delivery_channels` | `pito notifications channels list` | no | `--json` available. |
| Configure delivery channel | `PATCH /settings/delivery_channels/:id` | `pito notifications channels edit <id>` | no | interactive prompts for `enabled`, `digest_enabled`, `digest_at_local_time`, `immediate_kinds`. Webhook URLs are NEVER printed (encrypted at rest); to set, use `--webhook-url <url>`. |
| Add delivery channel | `POST /settings/delivery_channels` | `pito notifications channels add --kind discord\|slack --name "..." --webhook-url <url>` | no | |
| Remove delivery channel | `POST /deletions/delivery_channel/:ids` | `pito notifications channels remove <id>[,<id>...] --confirm yes` | no | bulk-as-foundation. |
| Test delivery (send a probe) | `POST /settings/delivery_channels/:id/test` | `pito notifications channels test <id>` | no | sends a test payload through the formatter. |
| Formatter preview | `GET /notifications/:id/preview/:format` | `pito notifications preview <id> --format discord\|slack\|in_app\|mcp` | no | renders the formatter output for a given notification + format. |

### Work unit 9 — MCP tool catalog expansion (phase folder `16-mcp-catalog-expansion/`)

This work unit adds MCP tools, not web actions. CLI is unaffected at the
subcommand level; existing CLI subcommands above hit the same Rails JSON API
the MCP tools wrap.

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| n/a | n/a | (none) | yes | This work unit is MCP-side. CLI parity is already declared per-domain above. |

### Pre-existing Phase 4 surfaces (already shipping; baseline parity)

These are NOT phases 8-16 but are baseline. Listed here for completeness so the
matrix is fully self-contained.

| Web action | HTTP | CLI subcommand | MCP | Notes |
| --- | --- | --- | --- | --- |
| List projects | `GET /projects` | `pito projects list` | yes (Phase 4) | |
| Show project | `GET /projects/:id` | `pito projects show <id>` | yes | |
| Create project | `POST /projects` | `pito projects add --title "..."` | yes | |
| Edit project | `PATCH /projects/:id` | `pito projects edit <id>` | yes | |
| Delete project | `POST /deletions/project/:ids` | `pito projects delete <id>[,<id>...] --confirm yes` | yes | |
| List footage in project | `GET /projects/:id/footage` | `pito footage list --project <id>` | yes | extends current `pito footage` group. |
| Import footage | `POST /projects/:id/footage` (multipart) | `pito footage import` | yes | already shipping today (Phase 4). |
| Edit footage | `PATCH /footage/:id` | `pito footage edit <id>` | yes | |
| Delete footage | `POST /deletions/footage/:ids` | `pito footage delete <id>[,<id>...] --confirm yes` | yes | |
| List notes | `GET /projects/:id/notes` | `pito notes list --project <id>` | yes | |
| Show note | `GET /notes/:id` | `pito notes show <id>` | yes | |
| Create note | `POST /projects/:id/notes` | `pito notes add --project <id> --title "..."` | yes | |
| Edit note | `PATCH /notes/:id` | `pito notes edit <id>` | yes | interactive opens `$EDITOR` per existing footage edit pattern. |
| Delete note | `POST /deletions/note/:ids` | `pito notes delete <id>[,<id>...] --confirm yes` | yes | |
| List saved views | `GET /saved_views` | `pito views list` | yes | already in `PitoClient`. |
| Open saved view | n/a | (web-only / TUI-only) | no | views resolve to web URLs; CLI subcommand isn't useful. |

### Cross-cutting subcommands (not domain-specific)

| Action | CLI subcommand | Notes |
| --- | --- | --- |
| Print help | `pito help` | already shipping. |
| Print version | `pito version` | already shipping. |
| Search | `pito search <query>` | hits `GET /search.json`; already supported in TUI. New subcommand surface gets `--json` + `--limit`. |
| Configure auth | `pito auth login` / `pito auth logout` / `pito auth whoami` | see work unit 2. |
| Token management | `pito tokens list` / `create` / `revoke` | see work unit 2. |
| Default TUI | `pito` (no args) | already shipping. |

## Per-subcommand spec template

Each `cli-impl` dispatch (per domain) implements the above subcommands using
this exact template. The template is mandatory; deviations require an
architect-spec amendment.

### Shape

```
pito <noun> <verb> [<positional>] [--flag value] [--flag yes|no]
```

- **Verb-first within a noun group.** Example: `pito videos publish 42`, not
  `pito publish video 42`. Nouns are plural; verbs are imperative.
- **Positional args** are the primary identifier (id) when applicable.
- **All boolean flags use `yes` / `no` strings** per CLAUDE.md hard rule. Never
  `--flag true`, `--flag 1`, `--flag` (bare). Always
  `--confirm yes` / `--unstar yes` / `--ack-game yes`.
- **All destructive or significant actions take `--confirm yes`.** Without it,
  the subcommand prints the action confirmation preview (matching the web's
  `_action_screen.html.erb`) and exits 0. With `--confirm yes`, the action
  fires.

### Standard flags (every subcommand)

| Flag | Type | Default | Purpose |
| --- | --- | --- | --- |
| `--json` | bool (presence-only) | absent | switches output to a single JSON document on stdout. Errors still go to stderr. |
| `--limit <n>` | u32 | 50 (list verbs) | caps result size on list verbs. Ignored on non-list verbs. |
| `--help` / `-h` | bool | absent | clap-generated help. Each subcommand has a one-line `about` and a multi-line `long_about`. |

Per-subcommand specific flags are listed in the matrix above and detailed in
each per-domain dispatch.

### Output formats

- **Default (TTY):** plaintext. Fixed-column tables for list verbs. Two-column
  key/value layout for show verbs. Color codes used when `stdout` is a TTY;
  fall back to plain when stdout is a pipe (per Open question recommendation:
  TTY detection on, default-on for color when TTY).
- **Default (non-TTY):** plaintext, no color codes.
- **`--json`:** a single JSON document. Schema mirrors the Rails JSON
  serializer's response 1:1 — same field names, same shape. Errors switch to
  `{"error": "...", "code": <int>}` on stderr while stdout is empty; exit
  code matches the error code per **Error handling** below.

### Error handling and exit codes

| Condition | HTTP | Exit code | stderr |
| --- | --- | --- | --- |
| Success | 2xx | 0 | (empty) |
| Validation error | 422 | 2 | `validation: <field> <message>` per error |
| Authentication failure (no / bad / expired token) | 401 | 3 | `auth: not authenticated. run \`pito auth login\`.` |
| Authorization failure (token lacks scope) | 403 | 4 | `auth: token missing scope <scope>` |
| Not found | 404 | 5 | `not found: <type> <id>` |
| Conflict (e.g., already syncing) | 409 | 6 | `conflict: <message>` |
| Rate limit | 429 | 7 | `rate-limited: retry after <seconds>` |
| Server error | 5xx | 10 | `server error <status>: <message>` |
| Network error (timeout, DNS, TLS) | n/a | 11 | `network error: <message>` |
| Confirmation required, not provided | n/a | 0 (preview is a non-error) | (empty); preview goes to stdout |
| Bad usage (clap parse error) | n/a | 64 | clap's standard message |

Exit codes 2-7 + 10-11 follow no specific platform convention but stay stable
across releases. They land in `extras/cli/src/output.rs` as a single
`ExitCode` enum mapped to `std::process::exit`.

### Help text style

- One-line `about` per subcommand. Imperative voice. No trailing period.
  Examples:
  - "Sync a channel from YouTube"
  - "Publish a video, with the four-item pre-publish checklist"
  - "List unread notifications"
- `long_about` is 2-5 lines, includes a one-line example, and points the user
  at the corresponding web URL when relevant. Example:
  ```
  Publish a video, with the four-item pre-publish checklist.

  Mirrors the web pre-publish modal at /videos/<id>/edit.
  Example:
    pito videos publish 42 --ack-game yes --ack-age yes \
      --ack-paid-promotion yes --ack-end-screen yes --confirm yes
  ```

## Auth configuration

### File location

`~/.config/pito/auth.toml` (XDG-compliant; recommended in the dispatch).
`$XDG_CONFIG_HOME` is honored if set.

### File shape

```toml
# Pito CLI authentication
# Generated by `pito auth login` or hand-edited.

[server]
url = "https://app.pitomd.com"

[token]
# Bearer token from /settings/tokens. Treat as a secret; never share.
value = "pito_xxxxxxxxxxxxxxxxxxxxxxxx"
```

- The file is `chmod 600` on creation. The `pito auth login` wizard enforces
  the mode; hand-edited files retain whatever permissions the user set, but the
  CLI emits a stderr warning on world-readable files (mode > 0600).
- `PITO_API_URL` env var, if set, overrides `[server].url`. Already supported by
  `extras/cli/src/api/http_client.rs`.
- `PITO_API_TOKEN` env var, if set, overrides `[token].value`. Useful for CI.
- The auth module fails fast with exit code 3 if neither file nor env vars
  resolve to a token, except for `pito help`, `pito version`, `pito auth login`,
  and the offline TUI smoke path (when `PITO_API_URL` is absent).

### Token rotation

v1 is file-edit + `pito auth login` only. No `pito auth refresh`, no automatic
refresh. The Open questions below capture the deferral.

## Crate structure

### Module layout

```
extras/cli/
├── Cargo.toml                          (existing)
└── src/
    ├── main.rs                         (existing — unchanged dispatch shape)
    ├── lib.rs                          (existing)
    ├── cli.rs                          (existing — clap tree expanded)
    ├── api/
    │   ├── mod.rs                      (existing)
    │   ├── client.rs                   (existing — PitoClient trait)
    │   ├── http_client.rs              (existing — gets bearer header)
    │   ├── models.rs                   (existing — typed payloads, expanded)
    │   ├── thumbnails.rs               (existing)
    │   └── yes_no.rs                   (existing)
    ├── auth.rs                         (NEW — reads auth.toml)
    ├── output.rs                       (NEW — JSON / plaintext / colors / exit codes)
    ├── confirm.rs                      (NEW — shared --confirm yes parsing + preview rendering)
    ├── commands/
    │   ├── mod.rs                      (existing — registers new modules)
    │   ├── tui.rs                      (existing)
    │   ├── help.rs                     (existing)
    │   ├── version.rs                  (existing)
    │   ├── footage.rs                  (existing)
    │   ├── auth.rs                     (NEW — login / logout / whoami)
    │   ├── tokens.rs                   (NEW — list / create / revoke)
    │   ├── channels.rs                 (NEW — list / show / add / star / edit / sync / delete / analytics / top-videos / insights)
    │   ├── videos.rs                   (NEW — list / show / edit / star / sync / delete / publish / schedule / unpublish / assign-project / analytics / retention)
    │   ├── projects.rs                 (NEW)
    │   ├── notes.rs                    (NEW)
    │   ├── games.rs                    (NEW — list / show / add / sync / import / edit / delete)
    │   ├── bundles.rs                  (NEW — list / show / create / add-member / remove-member / regenerate-cover)
    │   ├── calendar.rs                 (NEW — list / upcoming / show / add / edit / delete / mark-purchase / cancel-purchase / milestone-rules)
    │   ├── notifications.rs            (NEW — list / show / mark-read / mark-all-read / preview + channels submodule)
    │   ├── analytics.rs                (NEW — sync)
    │   ├── search.rs                   (NEW — search subcommand surface)
    │   └── views.rs                    (NEW — saved views list)
    ├── footage/                        (existing)
    ├── keys.rs                         (existing)
    ├── theme.rs                        (existing)
    ├── ui.rs                           (existing)
    ├── widgets.rs                      (existing)
    └── app.rs                          (existing)
```

### Entry-point dispatch

`main.rs` keeps its current shape; the match block expands to dispatch each new
top-level command to its `commands/<noun>.rs::run(args)` entry point. Per-noun
modules own their clap subcommand enum (declared in `cli.rs` for the top-level
tree) and implement an internal `run` that takes the parsed args + an
`&dyn PitoClient` + a `&dyn Output` (the new output trait). This keeps the
testability story consistent with the existing `commands/footage.rs` shape.

## Test posture (exhaustive)

Per Q7 (LOCKED): exhaustive Rust + integration tests. The bar for closing
each per-domain `cli-impl` dispatch is:

### Per-subcommand unit tests

Each `commands/<noun>.rs` ships co-located unit tests covering:

- **Argument parsing.** Each clap path: positional args, every flag, every
  enum value, missing-required-flag errors. Boolean discipline asserted on
  every yes/no flag.
- **Output formatting (plaintext).** Snapshot-style assertions on the rendered
  table / key-value layout. Use `insta` if added to dev-deps; otherwise raw
  string equality.
- **Output formatting (JSON).** Assert exact JSON shape per the Rails JSON
  serializer's expected response. Field-by-field equality via `serde_json::Value`.
- **Error translation.** Each HTTP status → exit code path tested with a
  mock client returning the corresponding error.
- **Confirmation gate.** For destructive verbs: a request without
  `--confirm yes` returns the preview (no HTTP POST fired); with `--confirm yes`,
  the POST fires.
- **Yes / no boolean discipline.** Any flag accepting `yes` / `no` is tested
  with both values, with invalid values (`true`, `false`, `1`, `0`) rejecting
  with exit code 64.

### Integration tests

Under `extras/cli/tests/integration_<noun>.rs`. End-to-end flow: spawn a
`wiremock` server, point `PITO_API_URL` at it, run the binary via
`assert_cmd`, assert exit code + stdout + stderr. One integration test per
subcommand happy-path; one per error class (auth fail, not found, validation,
network error). Use `wiremock::Mock` to assert the exact body sent for PATCH /
POST verbs (this is where the read-modify-write semantics for `pito videos edit`
get verified against note 1's destructive-PUT-per-part gotcha).

### Edge cases (mandatory coverage)

- Empty list responses (zero results); plaintext renders "no records" and
  exits 0; `--json` renders `[]`.
- Paginated list responses (more than `--limit`); the CLI honors the cap.
- Network errors (timeout, DNS); exit code 11 + stderr message.
- Auth failures (no token file, bad token, expired token); exit code 3.
- Stdout piped (non-TTY); colors stripped.
- Stdin not a TTY (interactive subcommand invoked from a pipe); falls back to
  required-flag mode and emits a clear stderr error if a required field has no
  flag value.
- `--json` + an interactive verb; the CLI errors out with "interactive prompts
  not supported with --json; provide all fields via flags" and exit code 64.

### TUI smoke

The default-mode TUI gets one smoke test per noun added to it (if any). Per
realignment + Open questions, the TUI's noun coverage is NOT expanded in this
work unit — only the existing TUI surface (channels, videos, dashboard,
search, footage, projects) is preserved. Calendar / notifications / games /
bundles do NOT enter the TUI in this work unit.

### Test gates per dispatch

A per-domain `cli-impl` dispatch closes only when:

1. `cargo test` is green.
2. `cargo clippy --all-targets --all-features -- -D warnings` is clean.
3. `cargo fmt --check` passes.
4. The manual playbook below runs end-to-end against a local Rails dev server.

## Manual playbook

This is the user-driven validation playbook the master agent runs at the close
of each per-domain dispatch.

### One-time setup (first dispatch only)

1. `cd /home/catalin/Dev/pito/extras/cli`.
2. `cargo build --release`.
3. Confirm `target/release/pito --version` prints something.
4. Open the Rails app at `http://localhost:3000/settings/tokens` (Phase 5 / 6
   surface). Mint a token with scope `app`. Copy it.
5. `pito auth login` — paste the token; choose `http://localhost:3000` as the
   server URL.
6. Verify `~/.config/pito/auth.toml` exists with mode 0600.
7. Run `pito auth whoami`. Expect printed user id + email + scopes.

### Per-domain validation

For each domain whose dispatch is closing, the user runs the matrix's
subcommands. Sample from the locked matrix:

1. `pito channels list` — confirm a fixed-column table.
2. `pito channels list --json` — confirm valid JSON; pipe through `jq .[0]`.
3. `pito channels show 1` — confirm key/value output.
4. `pito channels sync 1` — confirm preview output, no HTTP POST in logs.
5. `pito channels sync 1 --confirm yes` — confirm the sync fires; rerun
   `pito channels show 1` and verify `last_synced_at` updated.
6. `pito videos edit 1 --title "Test edit"` — confirm read-modify-write
   preserves other fields (verify via `pito videos show 1` after).
7. `pito videos publish 1 --ack-game yes --ack-age yes --ack-paid-promotion yes --ack-end-screen yes --confirm yes`
   — confirm the publish fires; check Studio for the privacy update.
8. `pito notifications list --json` — confirm valid JSON.
9. `pito calendar upcoming --days 30` — confirm upcoming entries print.
10. `pito games list` — confirm shelf entries print as a flat table.
11. Each enumerated subcommand for the domain in scope, happy path.
12. Negative path: `pito videos delete 999 --confirm yes` against a missing id
    — confirm exit code 5 + stderr `not found: video 999`.
13. Negative path: edit `~/.config/pito/auth.toml` to a garbage token, run
    `pito channels list` — confirm exit code 3 + `auth: not authenticated`.

### Test suite

`cd /home/catalin/Dev/pito/extras/cli && cargo test --all-features` — green.

### Lint

`cd /home/catalin/Dev/pito/extras/cli && cargo clippy --all-targets --all-features -- -D warnings`
— clean.

### Format check

`cd /home/catalin/Dev/pito/extras/cli && cargo fmt --check` — clean.

## Cross-stack scope

Per `CLAUDE.md`'s declared client surfaces:

- **Rails web (canonical).** In scope for every row in the matrix above; web
  is the source of truth.
- **MCP.** In scope per work unit 9 (separate dispatch). The matrix above
  records MCP yes/no per row for traceability.
- **Rust `pito` CLI.** In scope; this spec.
- **Cloudflare Pages landing page.** Out of scope; landing page does not
  surface any of these actions.

## Subcommand naming conventions (LOCKED)

These rules apply to every per-domain dispatch:

1. **Plural nouns.** `pito channels` not `pito channel`.
2. **Verb-first within a noun group.** `pito videos publish 42`, not
   `pito publish video 42`.
3. **Imperative verbs.** `add`, `edit`, `sync`, `publish`, `delete`,
   `mark-read`, `assign-project`. Never `added`, `updated`, `deleted`.
4. **Hyphen-case for multi-word verbs.** `mark-read`, `mark-all-read`,
   `regenerate-cover`, `assign-project`, `cancel-purchase`. Never `markRead`,
   `mark_read`, `markread`.
5. **Domain-bounded verbs.** Verbs may repeat across nouns when they mean the
   same thing (`list`, `show`, `add`, `edit`, `delete`, `sync`). Verbs unique
   to a domain stay in the domain (`publish` only on `videos`,
   `mark-read` only on `notifications`).
6. **Singular ids in positional args.** `pito channels show <id>` — one id.
   Bulk verbs accept comma-separated lists in the positional slot:
   `pito channels delete 1,2,3 --confirm yes`. This matches the
   bulk-as-foundation URL pattern `/<action>s/:type/:ids` in CLAUDE.md.

## Confirmation prompts (LOCKED)

Per CLAUDE.md hard rules:

- **No JS `confirm` / `prompt`.** Not relevant to CLI directly, but the
  philosophy carries: the CLI never blocks on a free-text "are you sure?"
  prompt. Confirmation is always `--confirm yes` (an explicit, scriptable
  flag).
- The interactive `pito videos edit <id>` flow uses prompts for *data entry*
  (title, description, etc.), not confirmation. After data entry, the CLI
  prints the diff and waits for `--confirm yes` (or, in interactive mode, a
  final "type 'yes' to apply" prompt that mirrors the action confirmation
  page's text).
- Error messages use lowercase, terse, no trailing period:
  `auth: not authenticated`. Never `Auth: Not Authenticated.`. Never
  `ERROR: ...`.

## Open questions

These are explicitly NOT blockers for this spec; they are decisions the user
makes (or defers) before the FIRST per-domain `cli-impl` dispatch closes. None
need answers before this spec is finalized.

1. **TUI scope expansion to new domains?** Recommendation (LOCKED in this
   spec): defer. TUI keeps its current shape. New domains are subcommand-only.
   If the user disagrees, this becomes a follow-up dispatch.
2. **`pito auth refresh` / token rotation flow.** Recommendation: file-edit
   + `pito auth login` for v1. No automatic refresh, no `auth refresh`
   subcommand. Revisit when token expiry becomes a real pain.
3. **Color output default.** Recommendation: TTY-detection on; color when
   stdout is a TTY, plain on pipe. Add `--no-color` and respect `NO_COLOR` env
   var per https://no-color.org. User confirms.
4. **Pagination default.** Recommendation: `--limit 50` default on every list
   verb. Server `?limit=N` query param respected. User confirms.
5. **Bulk-verb positional list separator.** Recommendation: comma (`1,2,3`).
   Matches the existing web URL pattern. Alternative would be repeated
   positionals (`pito channels delete 1 2 3`); rejected as ambiguous when a
   future verb takes a non-id positional.
6. **`pito videos edit` interactive editor for description.** Recommendation:
   open `$EDITOR` (fall back to `nano`) per the existing notes / footage edit
   pattern in the TUI. Non-interactive: `--description "..."` flag.
7. **`auth.toml` permissions enforcement.** Recommendation: warn (stderr) on
   mode > 0600, do NOT fail. Hard-fail would break copy-paste setups; warn
   keeps the user informed.
8. **Where do the new `commands/<noun>.rs` modules' clap structs live?**
   Recommendation: in `cli.rs` (top-level enum + per-noun sub-enums). Keeps
   the clap tree visible in one file. Per-noun module owns the runtime logic.
9. **`--json` output streaming for paginated list verbs.** Recommendation: no
   streaming in v1. The CLI fetches up to `--limit` and emits a single JSON
   array. Streaming (NDJSON / per-record stdout) is a follow-up if needed.

## Non-goals

- **TUI redesign.** The default `pito` TUI keeps its current channels / videos
  / dashboard / footage shape. No new TUI screens for calendar / notifications
  / games / bundles in this work unit.
- **New web actions.** This spec is mirroring-only. Adding a CLI subcommand
  whose web counterpart does not exist is out of scope.
- **Distribution / installer.** Per realignment work unit 12, deferred ~6
  months. `pito update` / `pito setup` / `pito backup` are NOT in this spec.
- **Cross-CLI / cross-MCP unification.** Each surface owns its own catalog;
  this spec only covers CLI parity. MCP catalog expansion is its own work
  unit 9.
- **`pito-sh` legacy compatibility.** The legacy paused `pito-sh` binary is
  not relevant; the unified `pito` binary supersedes it.
- **Web-only actions.** Explicitly listed `(web-only)` rows in the matrix
  above stay web-only. The architect re-evaluates only on an explicit
  user request.

## Acceptance

- [ ] Coverage matrix above enumerates every web action across realignment
      work units 2-8 (phases `09-mcp-scope-simplification/` through
      `15-notifications/`) plus baseline Phase 4 surfaces.
- [ ] Each row in the matrix maps a web action either to a `pito <noun> <verb>`
      subcommand OR to `(web-only)` with a one-line rationale.
- [ ] Subcommand naming conventions (verb-first, hyphen-case, plural nouns,
      imperative verbs, comma-separated bulk ids) are locked in this spec and
      referenced unchanged across every per-domain dispatch.
- [ ] Standard flags (`--json`, `--limit`, `--help`) are documented once;
      per-domain dispatches do not re-derive them.
- [ ] Auth file path locked: `~/.config/pito/auth.toml`. Schema locked.
      Override env vars (`PITO_API_URL`, `PITO_API_TOKEN`) locked.
- [ ] HTTP status → exit code translation table is locked. Each per-domain
      dispatch reuses it without redefinition.
- [ ] Crate structure is locked: per-noun module under `commands/<noun>.rs`,
      shared `auth.rs` / `output.rs` / `confirm.rs`. New entries in `cli.rs`
      enumerate clap subcommands.
- [ ] Test posture (per-subcommand unit tests + integration tests +
      `cargo clippy` + `cargo fmt`) is mandatory for every per-domain
      dispatch's close-out.
- [ ] Manual playbook is mandatory; user signs off before the dispatch's
      commit.
- [ ] Confirmation discipline (`--confirm yes`, no JS-style prompts) is
      enforced.
- [ ] Yes / no boolean discipline at every external boundary is enforced
      (per CLAUDE.md hard rule).
- [ ] Bulk-as-foundation (single id is `<id>`, multi is `<id>,<id>,...`) is
      enforced (per CLAUDE.md hard rule).
- [ ] Open questions are listed; none block this spec from being finalized.
- [ ] Non-goals are explicit; out-of-scope drift is a process failure.

## Dispatch sequencing recommendation

Each per-domain `cli-impl` dispatch fires **after** its corresponding Rails
spec lands and the Rails surface is real (controllers + routes + JSON
serializers shipping). Recommended order, mirroring the realignment roadmap:

1. **Tenant drop CLI cleanup** — strip `tenant_id` from `Channel` / fixtures.
   Fold into the tenant-drop dispatch's Lane 2a.
2. **Auth + tokens** — `pito auth *` and `pito tokens *`. Foundation for
   every domain that follows. Fold into work unit 2's Lane 2a.
3. **Channels** — work unit 3 Lane 2a.
4. **Videos** — work unit 4 Lane 2a. Read-modify-write semantics carry the
   load; merits its own dispatch.
5. **Analytics** — work unit 5 Lane 2a.
6. **Games + bundles** — work unit 6 Lane 2a. Two nouns; one dispatch is
   acceptable.
7. **Calendar** — work unit 7 Lane 2a.
8. **Notifications** — work unit 8 Lane 2a.

Each dispatch is small (1 noun group, 6-12 subcommands) and shares the
plumbing locked in this spec. The master agent dispatches them in the
realignment roadmap's order; per the realignment, units 6-8 can run in
parallel with units 3-5 once foundational plumbing (units 1-2) is in.

## Cross-references

- `docs/realignment-2026-05-09.md` — work unit 10 framing; resolved
  ambiguities 2/3 mirroring posture.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — the
  tenant-free posture every subcommand assumes.
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — `dev` / `app`
  scope catalog; the CLI's `app` scope is what every non-dev subcommand
  needs.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, yes/no
  boolean discipline, action confirmation framework).
- `extras/cli/CLAUDE.md` — agent file-scope for the `cli-impl` agent.
- Realignment work unit 9 (MCP catalog) — mirrors this surface on the MCP
  side. Per-row MCP yes/no in the matrix is the contract.
- `extras/cli/src/cli.rs` — current clap tree the matrix expands.
- `extras/cli/src/api/client.rs` — current `PitoClient` trait the new
  subcommands extend.
