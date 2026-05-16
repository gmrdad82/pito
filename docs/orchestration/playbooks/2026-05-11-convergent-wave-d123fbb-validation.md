# Manual test playbook — Convergent UI/UX wave (commit `d123fbb`)

**Branch:** `main` **Commit:** `d123fbb` — Convergent UI/UX wave (18 agents:
notifications, settings, channels, games, auth) **Diff range:**
`git log --stat 2959a2f..d123fbb` (118 files, +8251 / −1319) **Reviewer run:**
2026-05-11 19:50 (Europe/Berlin)

## Pipeline summary

- Code review: 1 concern (modal target-name inconsistency), several
  simplify-worthy notes — see below. No blockers.
- Simplify: 3 duplication opportunities identified, none blocking — see below.
- Test suite: **8154 examples, 18 failures, 1 pending** in a clean worktree at
  `d123fbb`. The 18 failures are NOT new in this commit — they reproduce on
  `2959a2f` (lint specs, notification cascade FK) or are environmental (race
  when multiple rspec processes share the test DB / pending migrations from
  in-flight parallel agent work that is NOT part of `d123fbb`). The
  d123fbb-touched spec files (channels / collections / games / settings / TOTP /
  IGDB / Voyage / notifications / cover component / filter chip / production env
  / omniauth / primary_genre / prepare_collections_for_shelf) all pass when run
  in isolation in a clean worktree.
- Brakeman: **3 warnings, all Weak confidence, all pre-existing** (not
  introduced by `d123fbb`): notifications/show LinkToHref weak XSS (existing
  notification.url linkout), totps/show CrossSiteScripting on ROTP/QR SVG
  (existing), composites_controller SendFile (existing — guarded by
  `Pito::AssetsRoot.path` validation). No NEW warnings.
- Bundler-audit: **0 advisories** (1080 advisories scanned; ruby-advisory-db up
  to date at commit `a6e58c70`).
- Rubocop (changed Ruby files only): **61 files, no offenses**.
- Cargo tests (`extras/cli/`): **all green** — 9 + 3 + 5 + 3 + 0 across the
  integration test crates; no regressions despite the Rust client consuming
  `/channels`, `/notifications`, and `/search` JSON whose UI layer changed (the
  JSON wire shape itself is untouched).

## Blockers

None. The pipeline is green for everything actually within this commit's scope;
the suite-level failures and Brakeman findings reproduce on the prior commit
(`2959a2f`).

## Concerns and suggestions

### Code review — concerns (non-blocking)

1. **Modal target naming inconsistency.**
   `app/views/games/_collections_modal.html.erb` sets
   `data-controller="confirm-modal"` on the `<dialog>` but uses
   `data-collections-modal-target="title"` / `="frame"` on the inner nodes. The
   `collections-modal` controller is never declared, so those `data-target`
   attributes are dead metadata as far as Stimulus is concerned. The
   `collections-modal-trigger` controller works around this by calling
   `dialog.querySelector('[data-collections-modal-target="title"]')` directly.
   Functional but confusing. Either declare a sibling `collections-modal`
   controller on the dialog (with `title` / `frame` targets) or drop the unused
   `data-*-target` attributes in favor of plain `data-role="title"` semantics.
   Filed for the docs / games agent in a future polish pass.

2. **Inline `<style>` block in `_genres_shelf.html.erb`.** Lines 31–38 add a
   `<style>` element inside the partial to draw the hairline between
   sub-shelves. The selector is scoped via
   `section[data-shelf="outer-genres"] > section.sub-shelf:not(:first-of-type)`
   so it only matches this surface, but inline `<style>` inside a partial is
   unusual for this project. Move to `app/assets/tailwind/application.css`
   alongside the other shelf rules in a follow-up.

3. **`[ clear all ]` bracket-padding rule drift.**
   `filter_row_component.html.erb` now emits `[ clear all ]` with inner spaces.
   The reviewer-doc rule (`docs/agents/reviewer.md` section A) says "Reject any
   new `[ label ]` (with inner padding) outside the `[ ]` / `[x]` checkbox
   shape." The comment in the partial cites the bracketed-link memory as the
   authority for adding spaces around multi-word labels, but that memory
   actually says "drop redundant nouns", not "add spaces". Pick one: either keep
   `[clear all]` flush (canonical `BracketedLinkComponent` shape) or add the
   space rule to the reviewer.md as an exception. Filed for the architect to
   adjudicate; no impact on user validation.

4. **Game `before_save :assign_primary_genre_if_blank` runs the picker over
   `game.genres.order(:name).first` BEFORE `game_genres` rows are persisted on
   new records.** If a controller creates a `Game` plus its `game_genres` in a
   single transaction via `accepts_nested_attributes_for` (or builds the join
   rows after `Game.create`), the picker may see zero linked genres at save time
   and leave `primary_genre_id` nil. Backfilled later by the next save once the
   joins exist. The `pito:backfill_primary_genres` rake task and the
   per-`GameGenre` model hook compensate; spec coverage exists
   (`spec/models/game_genre_spec.rb`). Flag is documentation: the comment in
   `game.rb` says "fires on every save", which is accurate, but a reader could
   mis-infer that single-pass create-with-genres "just works." A one-line note
   that the picker observes only PERSISTED genres would help.

5. **`igdb/client.rb` null-tolerant filter uses unbound IGDB OR syntax.** The
   change appends ` | category = null` to the where clause. This is documented
   IGDB Apicalypse syntax (per the inline comment with `Ghost of Tsushima`
   example) and the fix is correct — but parameter precedence on `where` chains
   in IGDB's query DSL is occasionally surprising. The spec at
   `spec/services/igdb/client_spec.rb` covers the happy path; if a user reports
   a regression where bundles / editions leak back in, re-check whether IGDB
   needs explicit grouping parentheses.

### Simplify — duplication opportunities (non-blocking)

1. **Theme-aware fallback-SVG image_tag pair.** The block:

   ```erb
   <%= image_tag image_path("game_cover_fallback_<modifier>_light.svg"),
                 ... data: { theme: "light" },
                 class: "game-cover-fallback game-cover-fallback--light" %>
   <%= image_tag image_path("game_cover_fallback_<modifier>_dark.svg"),
                 ... data: { theme: "dark" },
                 class: "game-cover-fallback game-cover-fallback--dark" %>
   ```

   appears in five places: `app/components/games/cover_component.html.erb` (×2 —
   link path and non-link path), `app/views/games/_tile.html.erb`,
   `app/views/games/_collection_tile.html.erb`,
   `app/views/games/_list_mode.html.erb`,
   `app/views/shared/_igdb_cover.html.erb`. Extract a
   `game_cover_fallback_tag(variant:, **html_options)` helper or a shared
   partial. Saves ~60 LOC and centralizes the asset-naming contract.

2. **AppSetting update_X form-handler duplication.**
   `SettingsController#update_voyage` and `SettingsController#update_youtube`
   share the same shape: iterate a `FIELDS` constant, read
   `params.dig(:settings, "clear_#{field}")` and `params.dig(:settings, field)`,
   branch on `"yes"` for clear / `present?` for replace / no-op. Pull into
   `update_appsetting_section(fields:)` and call once per section. The next
   migrated credentials block (Slack / Discord per the follow-ups) will get this
   for free.

3. **`prepare_collections_for_shelf.rb` rescue-and-log block.** The
   `rescue StandardError => e ; @logger.warn(...) ; end` pattern is the third
   copy of the "iterate-and-soft-fail" wrapper in this commit (also in
   `youtube_credentials_backfill.rake` and the per-collection composer call
   site). A tiny `safe_each(...) { ... }` shared helper would tighten this;
   non-urgent.

### Surface-specific notes

- **Settings stack:** the new `@notes_volume_status`, `@assets_breakdown`,
  `@notes_breakdown`, `@sidekiq_breakdown`, `@postgres_table_breakdown`,
  `@search_per_index_stats`, `@redis_status` ivars all flow through the
  controller's defensive `rescue` paths. None of them raise on a missing
  Postgres column / unreachable Redis / unhealthy Meilisearch — the matching
  view branches surface a muted em-dash. Verified by reading
  `SettingsController#index` and the matching helper methods.

- **P25 F1 (force_ssl) + F2 (trusted_proxies) hardening:** the change is gated
  behind `Rails.env.production?` via the `production.rb` file. Test environment
  is unaffected. The lint spec `spec/config/production_env_spec.rb` source-greps
  the file and pins the assume_ssl / force_ssl / trusted_proxies / IPAddr /
  Cloudflare range / refresh-date constraints. Cloudflare list refresh date is
  2026-05-11; flag a follow-up to re-encode the list around 2027-05.

- **TOTP password + code gate (disable + regenerate backup codes):** failure
  copy is "credentials don't match." (generic) — confirmed not to leak which
  field failed. Session-token rotation is preserved on the disable path.

- **Notifications inbox `<thead>` row:** spans 5 columns (select / kind / title
  / severity / when). The `select` column is empty in the thead which is a minor
  visual oddity but matches the videos / channels picker pattern.

## Manual test steps

Numbered checklist for the operator. Each step assumes the user is running
`bin/dev` and signed in.

### Setup preamble (terminal, before opening the browser)

1. **Stop any running `bin/dev` session.** `Ctrl+C` in the terminal that started
   it, or `pkill -f puma` if needed.

2. **Park untracked migrations from in-flight parallel agents.**

   ```bash
   ls db/migrate/20260512* 2>/dev/null
   ```

   If files are present, those belong to another agent's session and are NOT
   part of commit `d123fbb`. Move them aside before validating so the boot path
   is deterministic:

   ```bash
   mkdir -p /tmp/pito-other-agents-migrations
   mv db/migrate/20260512* /tmp/pito-other-agents-migrations/ 2>/dev/null || true
   ```

3. **Clear bootsnap + tmp.** The omniauth initializer now reads from the
   AppSetting singleton at boot; bootsnap can cache the old shape.

   ```bash
   rm -rf tmp/cache/bootsnap tmp/cache/assets
   ```

4. **Apply the two new migrations** (idempotent if already migrated):

   ```bash
   bin/rails db:migrate
   ```

   Should report `AddYoutubeCredentialsToAppSettings` and
   `AddPrimaryGenreIdToGames` as up-to-date.

5. **Backfill YouTube credentials from `credentials.yml.enc` into AppSetting**
   (idempotent — re-runs are safe; the task NEVER overwrites a non-blank
   AppSetting value):

   ```bash
   bin/rails pito:backfill_youtube_credentials
   ```

   Expected: `youtube credentials backfill: wrote N column(s): <list>.` (or
   `nothing to do` on a re-run).

6. **Backfill primary genres** (idempotent):

   ```bash
   bin/rails pito:backfill_primary_genres
   ```

7. **Re-seed the demo collections** (this rev renames `Demo Collection` →
   `currently playing` and adds a `now playing` 2-game demo):

   ```bash
   bin/rails db:seed
   ```

8. **Start the app fresh:**
   ```bash
   bin/dev
   ```
   Watch the boot log: no "missing google_oauth credentials" raise. If the raise
   fires, AppSetting + credentials + ENV all returned blank; set values in
   `Settings → YouTube → [update]` (you can still log in first as long as the
   install isn't using Google OAuth for its own login).

### Quality-gate verification

9. **Brakeman** clean apart from 3 pre-existing weak warnings:

   ```bash
   bundle exec brakeman -q
   ```

   Expected: `Security Warnings: 3` (Cross-Site Scripting × 2 + File Access × 1)
   — all weak, all pre-existing.

10. **Bundler-audit** clean:

    ```bash
    bundle exec bundler-audit check --update
    ```

    Expected: `No vulnerabilities found`.

11. **Rubocop** clean on the changed files (full sweep optional):
    ```bash
    git diff --name-only 2959a2f..HEAD -- '*.rb' | xargs bundle exec rubocop --force-exclusion
    ```
    Expected: `no offenses detected`.

## User Validation

Walk through these in the browser only. Each step is a click + observation; no
terminal needed.

[ ] 1. **Boot smoke test.** Visit `/` → page loads with no banner; `bin/dev` log
shows no "missing google_oauth credentials" raise.

[ ] 2. **Settings — db pane.** Visit `/settings`, scroll to the integrations
row, then to the **db** heading (was `sql`). Verify: heading reads `db`.
Postgres column shows a per-model breakdown table only (no version / db-name /
totals row). A horizontal hairline separates Postgres from Redis. Redis
sub-section shows a Sidekiq job-state breakdown table with a 2-row grouped
header (`successful | failed` over
`busy | scheduled | enqueued | retry | dead`).

[ ] 3. **Settings — storage pane.** Two columns: `assets` (renamed from
`pito-assets`) and `notes`. Each shows a per-subcategory table (assets: cover
arts | thumbnails | banners | other; notes: namespace | count | size). No path
string under either heading. The right-side cell from the previous "Redis
standalone" pane is gone — the row is single-column.

[ ] 4. **Settings — search pane.** Meilisearch shows a per-index table
(`index | documents | size`). No total-index-size summary line. Below it, Voyage
embeddings shows the per-target toggles and the encrypted-storage hint
"credentials stored encrypted in the database; never echoed".

[ ] 5. **Settings — YouTube pane.** Voyage-style form, not a status card. Four
inputs (`youtube_api_key`, `youtube_client_id`, `youtube_client_secret`,
`youtube_redirect_uri`). Sensitive fields show `••••••• key configured`
placeholder; non-sensitive fields show the stored value as the placeholder. Each
configured field renders a `clear stored <field>` checkbox. Submitting the form
with all inputs blank is a no-op (no overwrite).

[ ] 6. **Settings — YouTube rotation.** Type a new value into one field, leave
the others blank, submit. The pane re-renders with the new placeholder; the
other three fields keep their prior values. (Edit a non-sensitive field like
`youtube_redirect_uri` so the new value is verifiable in the placeholder.)

[ ] 7. **Notifications — `<thead>` + legend at bottom.** Visit `/notifications`.
The table has a `<thead>` with columns
`select | kind | title | severity | when`. Glyph legend (📺, 🎮, 🚨, …) is below
the table, laid out as a 2-column grid with one `<emoji> <kind>` pair per line.
Each kind label is on its own row (no comma-separated single-line form).

[ ] 8. **Channels picker — sort + URL cell.** Visit `/channels`. Headers:
`name | URL | subs | videos | star | synced` (note: `subs` was `subscribers`;
`synced` was `last sync`). The `subs`, `videos`, `star`, `synced` columns sort
on click; sorting `subs` asc puts null rows last, desc puts them first. The URL
column shows the channel handle (`@xxx`) as a link with `href` to YouTube; the
channel title is in the name cell only (no muted sub-line). The `[ ] starred`
chip above the table is OUTSIDE the channels-index-table frame; clicking it
actually flips to `[x] starred` and adds `?star=yes` to the URL (no Turbo Frame
stale-DOM bug).

[ ] 9. **Games — filter row.** Visit `/games`. Display-mode switcher (`grid` /
`list` / `shelves-by-letter`) is in the filter row's right slot (was previously
flush right of the `<h1>` row). Filter chips render as `[ ] label` (unchecked) /
`[x] label` (checked). Clicking a chip toggles its token in the `?filters=` CSV.
The `[ clear all ]` link clears all chip tokens but preserves `?genre=` /
`?collection=` / `?display=` overrides.

[ ] 10. **Games — Genres outer shelf.** Below the H1, find the `genres` shelf.
Sub-shelves render one per genre that has a primary-pinned game. Headings are
lowercase (`adventure`, `platformer`, `rpg`); the `RPG` acronym is preserved as
an exception. Hairlines separate consecutive sub-shelves (but not before the
first or after the last). A multi-genre game (e.g. an RPG/Adventure title)
appears in EXACTLY ONE sub-shelf.

[ ] 11. **Games — Collections outer shelf.** Heading reads `collections` (was
`custom collections`). Single horizontal-scroll row, one tile per collection.
The `now playing` demo collection (Pragmata + RDR2) renders a composite cover.
Click a collection tile → a modal opens listing that collection's games as
`t_cover_big` tiles. Click a game tile → navigates to the game's show page.
Closing the modal (Escape or `[close]`) returns to `/games` without a reload.

[ ] 12. **Games — list display mode.** Switch to `[list]` via the filter-row
right slot. The table columns are
`cover | title | release year | rating | platforms owned |         genres | status`.
No white spacer rows between letter groups. Year is NOT inline in the title;
rating shows `★ NN` muted via `STAR_GLYPH`. Missing covers render the
theme-aware fallback SVG, not the text `[no cover]`.

[ ] 13. **Games — fallback SVGs across grid and shelf variants.** Find at least
one game with no cover image. Verify the fallback SVG renders (not text). Toggle
the theme between light and dark via the theme switcher in the page header; the
correct light or dark variant SVG becomes visible.

[ ] 14. **Projects — picker table shrink-to-fit.** Visit `/projects`. The table
no longer stretches to the full 1100px width; numeric columns (`created`,
`footage`, `notes`, `videos`) hug their content. The name column is 260px and
remains readable.

[ ] 15. **2FA — enrollment.** Visit `/settings/security/totp` → `[enable 2FA]`
(bracketed, no inner spaces). Scan QR or copy seed; enter a fresh code;
`[confirm 2FA]` → success flash. Backup-codes page shows.

[ ] 16. **2FA — disable with password + TOTP gate.** Visit
`/settings/security/totp` (now enrolled) → `[disable 2FA]`. The destroy screen
asks for BOTH password AND a fresh 6-digit code. Submit with only the code
(leave password blank) → "credentials don't match." (generic copy — no leak
about which field failed). Submit with both correct → 2FA disabled; the session
token rotates (existing cookie no longer valid on a new tab).

[ ] 17. **2FA — regenerate backup codes (same gate).** Re-enroll, then go to
`/settings/security/totp/backup_codes` → `[regenerate]`. Same password + code
gate; same generic failure copy on a mismatch.

[ ] 18. **IGDB search modal.** From a `/games/new` flow or any page where the
`[add from IGDB]` modal opens, type a query that previously returned no results
because of a null `category` filter (e.g. `Ghost of Tsushima`). The modal opens
at 720px max-width (no horizontal scrollbar; the `[search]` button is fully
visible). Results include the main entry plus remasters / ports; bundles +
packs + collection editions are filtered out.

## Cleanup

Roll-back commands if a retry from scratch is needed:

```bash
# Discard local changes (preserves the parked migrations from
# parallel-agent work).
git restore --staged --worktree .

# Restore the parallel-agent migrations if you want to keep working
# on that branch:
mv /tmp/pito-other-agents-migrations/* db/migrate/ 2>/dev/null || true

# Reset the dev DB to a known state (re-runs every migration + seeds):
bin/rails db:drop db:create db:migrate db:seed

# Restart bin/dev:
bin/dev
```

If the AppSetting YouTube columns hold values you no longer want, clear them
from `/settings` via the per-field `clear stored ...` checkboxes (single
submit), then re-run `pito:backfill_youtube_credentials` to re-seed from
`credentials.yml.enc`.
