# Security review — Wave 1 + Wave 1.5 + Wave 2 polish bundle

**Branch:** `main` (uncommitted working tree) **Audit date:** 2026-05-06
**Scope:** 66 files modified / 5 added since `f4b8c68` — Phase 4 Wave 1 + 1.5 +
2 polish, no auth, no new secrets paths.

## Pipeline run summary

- `bundle exec brakeman -q -A -w1` (strict): 0 new findings. Pre-existing
  baseline = 1 ForceSSL (production config) + 20 Weak-confidence UnscopedFind
  (single-tenant by design). None introduced by this diff.
- `bundle exec bundler-audit check --update`: 0 vulnerabilities (advisory DB up
  to date through 2026-03-30).
- `cargo audit`: not installed locally — pre-existing follow-up #4 in
  `docs/orchestration/follow-ups.md`. Not regressed by this diff.
- Manual `/security-review` style audit of every changed file: see findings.
- Hard-rule grep (`data-turbo-confirm`, `window.confirm`, `alert(`, `prompt(`):
  only documentary mentions in comments, no new violations.

## Findings

### F1. `application_helper.rb#version_label` link uses `rel: 'noopener'` without `noreferrer`

- **Severity:** Informational
- **Location:** `app/helpers/application_helper.rb:108`
- **Description:** `link_to(sha, repo_url, target: '_blank', rel: 'noopener')`
  omits `noreferrer`. The `repo_url` is built from `git rev-parse --short HEAD`
  (server-controlled, not user input), so there is no tab-napping or
  referrer-leak vector today. Noted only because the diff scope summary asked
  for blanket `target="_blank"` audit.
- **Out of diff scope:** this file is unchanged in the current bundle. Not
  regressed by Wave 1/1.5/2.
- **Recommendation:** if/when the file is touched, add `noreferrer` for
  consistency with the new `_pane.html.erb` / `_picker.html.erb` /
  `videos/index.html.erb` pattern. No action required for this commit.

### F2. `filesize_bytes` strong-params drop in both Footages controllers — RESOLVED

- **Severity:** Informational at audit time; functional blocker called out by
  reviewer; **resolved by post-audit patch.**
- **Location:** `app/controllers/api/footages_controller.rb#build_create_attrs`,
  `app/controllers/footages_controller.rb#build_update_attrs`.
- **Description:** CLI sends `filesize_bytes` in create / update bodies; Rails
  strong-params silently stripped the field. Column would never be populated
  through any external surface.
- **Resolution:** Both permit lists now include `:filesize_bytes`. Round-trip
  specs added. Smoke
  `curl -X POST .../footages.json -d '{"footage":{...,"filesize_bytes":98765}}'`
  returns `filesize_bytes: 98765` (was `None`).

## Confirmed-clean checklist

Each of the following was audited and passed:

- **`<title>` SafeBuffer fix (`app/views/layouts/application.html.erb:12`).**
  `safe_join([yield(:title), " ~ pito"])` consumes the SafeBuffer that
  `content_for(:title, value)` produced (Rails escapes a non-safe `value` on the
  way in). The static literal `" ~ pito"` contains no metacharacters;
  `safe_join` correctly escapes any non-safe piece. **No new XSS hole.** The
  previous interpolation was an output-encoding bug (double-escaped
  `&amp;#39;`), not a vulnerability — the fix is a strict improvement.

- **`projects_controller.rb` SQL allowlist (Wave 2 Lane F + H).** Both
  `#sort_clause` (line 123-131) and `#ordered_footages` (line 206-221) build
  `Arel.sql("#{column} #{direction}")` from frozen-hash allowlist lookups
  (`ALLOWED_SORTS`, `FOOTAGE_SORT_COLUMNS`, `ALLOWED_DIRS`). Brakeman's flow
  analysis accepts both at `-w1`. The `dir` value is downcased and explicitly
  intersected with `ALLOWED_DIRS` before splicing. The `column` value is
  selected from a frozen hash keyed by `params[:sort]` with a default fallback.
  Pattern matches `ChannelsController#sort_clause`. Specs exercise
  `sort=drop_table_projects` and `dir=sideways` to confirm allowlist enforcement
  (`spec/requests/projects_spec.rb:131-156`). **No SQL injection vector.**

- **`projects_controller.rb` filter parameters (`#filtered_footages`, line
  183-204).** All filters use parameterized `where(column: value)` form.
  `params[:fps]` is coerced via `BigDecimal(...)` with an `ArgumentError`
  rescue; `params[:bit_depth]` is coerced via `.to_i`; `params[:source]` is
  intersected with `Footage.sources.key?` before query. **All parameterized; no
  string-interpolation into SQL.**

- **Migrations:** `AddFilesizeBytesToFootages`, `AddCounterCachesToProjects`,
  `BackfillProjectCounterCaches`. Static schema operations; no params, no
  interpolation. `Project.reset_counters(project.id, assoc)` takes a
  server-derived `project.id` and a frozen-list association symbol
  (`%i[footages notes timelines]`). Reflection guard
  (`Project.reflect_on_association(assoc)`) further validates. Reversible. **No
  injection vector.**

- **YouTube `target="_blank"` links.** All three new/modified instances carry
  `rel="noopener noreferrer"`:
  - `app/views/channels/_pane.html.erb:9, 11`
  - `app/views/channels/_picker.html.erb:73`
  - `app/views/videos/index.html.erb:61`

  The `channel.channel_url` value is locked at create time
  (`Channel#prevent_url_change`) and validated against the strict
  `CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}`.
  **No `javascript:` / `data:` URL injection vector. No tab-napping.**

- **`bulk_select_controller.js` (always-on bulk).** All dynamic content paths
  (`count`, `delete N`, `sync N`, `_setHint`, `_setBracketedLink`,
  `_setMutedBracketed`) use `document.createTextNode` or `textContent`
  assignment. The URL construction uses `cb.value` (server-rendered numeric
  record IDs) and the data-value `deleteType` / `syncType` (controlled string
  from the controller-root attribute). No `innerHTML`, no `eval`. **No XSS
  vector via the always-on bulk extension.**

- **`FilterChipComponent`.** Builds hrefs from `@current_params.to_query` (Rails
  URL-encoded). Label rendered through ERB auto-escape. **No injection.**

- **`projects/_footage_pane.html.erb:65`
  `link_to("#{label}#{arrow}".html_safe, href)`.** Both `label` and `arrow` are
  static literals from the partial source (`"filename"`, `" ▲"`, etc.); no user
  input flows into the marked-safe string. Fine.

- **API serializer changes (`Api::FootagesController#footage_json`,
  `FootagesController#footage_json`).** `fps&.to_f` is a numeric coercion,
  `filesize_bytes` is an integer column. No new sensitive field exposed (no
  tokens, no encryption keys, no `AppSetting` nor `Voyage` material).

- **CLI Rust changes.** `ffprobe::file_size_bytes` calls `std::fs::metadata` on
  a path produced by `scan_directory(--path)` — same trust boundary as the
  existing probe walk. `middle_truncate` uses `chars().count()` indexing (no
  byte-boundary slicing on multibyte UTF-8; the test fixture confirms). No new
  `unsafe`, no new shell-out, no new deserialization, no new file-write paths.

- **Counter-cache columns.** `footages_count`, `notes_count`, `timelines_count`
  are integer counters; counter-cache writes go through Rails-managed paths with
  no raw SQL. Backfill via `Project.reset_counters` (server-controlled args).

- **Pito hard rules.** No new `data-turbo-confirm`, `window.confirm`, `alert(`,
  `prompt(`. Yes/no boundary: no new external boolean surfaces (the existing
  `has_commentary_track` round-trip is preserved). No new `.env*` reads, no new
  `Rails.application.credentials` paths. Sidekiq Web auth, CSP, and the existing
  rate-limit posture (none — pre-auth phase) are unchanged.

- **`Current.tenant` / `Current.user` boundary.** No diff touches
  `ApplicationController`, `Current`, or the seeded-singleton flow. Pre-existing
  UnscopedFind warnings are consistent with the architecture.

## Verdict

**CLEAR TO MERGE** (after F2 fix, which has landed).

## Summary

- Critical: 0
- High: 0
- Medium: 0
- Low: 0
- Informational: 2 (F1 = unchanged file outside diff; F2 = resolved by
  post-audit patch).
