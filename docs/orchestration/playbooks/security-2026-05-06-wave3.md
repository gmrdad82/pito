# Security review — Phase 4 Wave 3 (pane CSS + notes always-on + list polish)

**Branch:** `main` (uncommitted) **Specs covered:** Lane I (pane color tokens),
Lane J (notes always-on bulk), Lane K (list table polish) **Audit run:**
2026-05-06

## Diff summary

Three rails-only lanes, view-dominant. Lane I introduces three CSS pane-bg
tokens (`-a`, `-b`, `-wide`) in light + dark and applies them via static
inline-style values on four show/index pages. Lane J removes the
`[bulk]`/`[cancel]` toggle gates and `hidden` checkbox columns from the project
notes pane — the bulk toolbar now renders always, with self-hide driven by the
existing `bulk-select` Stimulus controller. Lane K inserts a `Name` column
(linking `channel.id` / `video.id` to the show page) into channels picker and
videos index, drops the `[o]` action column from the projects index, adds `"id"`
to `ChannelsController::ALLOWED_SORTS`, and declares a new forward-looking
`ALLOWED_SORTS`/`ALLOWED_DIRS` pair on `VideosController` (not consumed by
`index` yet). Plus a small CSS post-fix restoring full-width on `:only-child`
panes (show pages were inheriting the multi-pane 454px width). No schema, auth,
MCP, secrets, JS controller, route, or Rust changes.

## Pipeline run summary

- `bundle exec brakeman -q -A -w1`: 21 warnings — all pre-existing (1
  `force_ssl` config note, 20 `UnscopedFind` weak-confidence findings tied to
  the Phase-pre-auth seeded-singleton tenant model documented in `CLAUDE.md`).
  Zero new findings introduced by Wave 3.
- Inline-style audit (`grep 'style="..<%'`): zero ERB interpolation inside any
  `style="..."` attribute in any of the four touched view files. Every value is
  a static CSS literal.
- `raw` / `html_safe` audit on the eight changed view files: zero hits.
- Hard-rule grep (`window.confirm`, `alert(`, `prompt(`, `data-turbo-confirm`):
  only the pre-existing `unsaved_form_controller.js` comment-line (documented
  `beforeunload` exception). No new violations.
- `ALLOWED_SORTS` consumer review: `ChannelsController#sort_clause` looks up
  `params[:sort]` against the frozen hash and falls back to `"created_at"`;
  `params[:dir]` is gated through the frozen `ALLOWED_DIRS` allowlist. The new
  `"id"` entry inherits the same safe handling. `VideosController` declares the
  constants but does not yet thread them into `Video.order(...)` — the index
  action remains `order(published_at: :desc)`, so the constants cannot be used
  unsafely today.

## Findings

None.

## Confirmed-clean checklist

- Lane I — Inline-styled pane wrappers (projects/show, settings/index,
  channels/show, videos/show): all `style="..."` values are static literals. No
  request param, model attribute, or user-supplied value reaches any inline
  style. CSS-token names are baked-in strings.
- Lane I — New CSS tokens (`--color-pane-bg-a/-b/-wide`) are applied via
  existing `.pane-wrapper` + `:nth-child(even)` + `:only-child` selectors. No
  scripted styling, no JS surface.
- Lane J — Notes pane always-on bulk: the markup change is purely visibility
  (`hidden` removed, target gates removed). The destructive endpoint flow
  (`/deletions/note/:ids` via `Confirmable`) is untouched; deletion still
  requires user checkbox interaction + `[delete N]` click + the action-screen
  confirmation. No new `data-turbo-confirm`, `confirm()`, `alert()`, or
  `prompt()` introduced. No new attribute or Stimulus action is exposed; the
  deletion still rides the existing CSRF-protected POST through the Rails forms
  machinery.
- Lane K — `link_to channel.id, channel_path(channel)` and
  `link_to video.id, video_path(video)`: PK is integer, URL is built by a Rails
  helper. No XSS, no path injection.
- Lane K — `ChannelsController::ALLOWED_SORTS` gains `"id" => "channels.id"`:
  consumed only via frozen-hash lookup in `sort_clause`. Direction is
  allowlisted. Final `Arel.sql("#{column} #{direction}")` is composed strictly
  from server-controlled values. Safe.
- Lane K — `VideosController` `ALLOWED_SORTS` / `ALLOWED_DIRS` constants:
  declared but not yet wired into `index`. Cannot be used unsafely from any
  current code path. Forward-looking parity with channels.
- Hard rules — `yes`/`no` boundary discipline, secrets in credentials, no JS
  confirm/alert/prompt: untouched.
- CSP: no new scripts, no new style-src dynamism (inline styles already
  permitted by the existing CSP). No CSP impact.

## Out-of-scope but noted

- Pre-existing `UnscopedFind` warnings (20) on Channel / Video / Project / Note
  / Collection / Timeline finders are an artifact of the
  seeded-singleton-tenant-only phase. They become real findings once Auth
  Foundation introduces multi-tenant request scoping. Not a Wave 3 issue.
- `config.force_ssl` not enabled — operational concern delegated to the
  Cloudflare tunnel termination per existing posture. Not a Wave 3 issue.

## Verdict

**CLEAR TO MERGE / ready-to-commit.**

## Summary

- Critical: 0
- High: 0
- Medium: 0
- Low: 0
- Informational: 0
