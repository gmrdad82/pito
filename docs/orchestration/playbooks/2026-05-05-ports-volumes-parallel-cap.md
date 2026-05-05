# Manual test playbook — ports / volumes / parallel-test cap

**Branch:** `main` (uncommitted) **Spec:** infra-only bundle, no
`docs/plans/...` spec — request was issued in-session as a coordinated infra
pass covering three concerns:

1. Pito-specific high host ports (`27` suffix marker) so `bin/dev` coexists with
   sibling projects (e.g. fepra2-api on `3018` / `64518`).
2. Docker volumes renamed to single-prefix `pito-postgres-data`,
   `pito-redis-data`, `pito-meilisearch-data` (plus reserved `pito-notes`,
   `pito-assets`).
3. `parallel_tests` workers capped at 8 in CI yml, `bin/parallel_setup`, and the
   new `bin/test` wrapper.

**Reviewer run:** 2026-05-05 19:19

## Pipeline summary

- Code review: pass (1 documentation drift, 1 minor consistency note — both
  non-blocking, see below).
- Simplify: pass (1 minor DRY observation about the cap value `8` repeated in
  three places — non-blocking, intentional per `bin/test` comment).
- Test suite (`bin/test spec/`): **1059 examples, 0 failures**, 0 pending.
  Wrapper validated end-to-end at 8 workers.
- Rubocop: clean. 280 files inspected, no offenses.
- Brakeman: clean. 0 security warnings (Rails 8.1.3, Brakeman 8.0.4, all default
  checks).
- Bundler-audit: clean. ruby-advisory-db updated, no vulnerabilities.
- `docker compose config --quiet`: valid.
- Volume audit (`docker volume ls | grep pito`): exactly the three expected
  names — `pito-postgres-data`, `pito-redis-data`, `pito-meilisearch-data`.
  (Plus `fepra2-api-redis-data` from a sibling project — clearly identifiable by
  prefix, which is the whole point of the rename.)
- CI yml `PARALLEL_TEST_PROCESSORS: "8"`: present in the rails-job env block
  (line 92).
- Port collision check: pito's containers bind `127.0.0.1:54327`, `:64527`,
  `:7727`; fepra2-api's containers bind `127.0.0.1:64518`, `:33068`. Both stacks
  healthy side-by-side at review time. No address-in-use conflict.
- Hard-rule audit: no new `data-turbo-confirm`, `window.confirm`, `alert(`,
  `prompt(` in the diff (infra-only bundle).
- Yes/no boundary check: N/A (no external boolean changes in the diff).
- Secrets-in-`.env` check: `.env.example`, `.env.development`, `.env.test`
  contain only host / port / URL / non-secret config (`MAX_PANES`,
  `PANE_TITLE_LENGTH`, `PITO_*_PATH`). Postgres credentials remain in Rails
  encrypted credentials per `CLAUDE.md`.
- 127.0.0.1 binding check: every host-port mapping in `docker-compose.yml` uses
  `127.0.0.1:NNNNN:CCCC`. No bare `0.0.0.0`-style bindings.

## Blockers

None.

## Concerns and suggestions (non-blocking)

1. **`MEILI_PORT` vs `MEILISEARCH_PORT` mismatch.** `docs/setup.md` (line
   109, 122) documents the override env as `MEILI_PORT`, but
   `docker-compose.yml` line 40 reads `${MEILISEARCH_PORT:-7727}`. A user who
   follows the doc and sets `MEILI_PORT=...` will see no effect. Pick one and
   align: either rename the compose variable to `MEILI_PORT` (with an optional
   fallback to `MEILISEARCH_PORT` for back-compat, since `MEILISEARCH_URL` is
   already used at the Rails layer in
   `app/services/search/meilisearch_engine.rb` and would benefit from a
   consistent prefix), or correct the docs to say `MEILISEARCH_PORT`. Easy fix;
   doesn't block the validation walk-through.

2. **Stale port reference in `docs/agents/mcp.md` line 9** ("dedicated Puma on
   port 3001"). Outside this diff's modified-files list. The file was committed
   in `b833b12` (agent stubs) and the docs sweep didn't pick it up. Single-line
   fix; non-blocking. Older `docs/orchestration/playbooks/` files also reference
   3000/3001/5433/6380/7700 — those are historical session records and should
   NOT be retroactively edited.

3. **Cap value `8` hard-coded in three places** (`bin/test`,
   `bin/parallel_setup`, `.github/workflows/ci.yml`). The `bin/test` comment
   already calls this out ("matches CI and bin/parallel_setup"). Three
   touch-points across two ecosystems (bash + GH Actions yaml) is the common
   pattern here; a shared shell snippet would be over-engineered. Flagging only
   so a future bump (say to 12 on a beefier runner) is remembered to land in all
   three.

4. **`config/database.yml` reads `POSTGRES_PORT` at `54327` default;
   `.github/workflows/ci.yml` rails-job env still sets `POSTGRES_PORT: 5432` for
   the GH Actions Postgres service container.** This is correct (CI's bare-metal
   Postgres uses the default port; the dev compose stack uses the relocated
   port) but easy to misread. Just confirm during walk-through that CI runs
   green after this lands — the env-driven design means it should, and the
   existing Phase log shows previous CI runs unaffected by port-default changes.

5. **`.env.development` and `.env.test` are tracked working-tree files (not in
   `.gitignore`).** Reading them showed they contain only host / port data, no
   secrets — consistent with the project's secrets policy. Worth a quick
   gut-check that the user is comfortable shipping them committed (this isn't
   new behaviour from the bundle, it's the pre-existing state).

## Manual test steps

Hands-on walk-through. Pace ~5–10 minutes. Steps assume a clean shell at
`/home/catalin/Dev/pito`.

### 0. Confirm the working tree

```bash
git status
```

**Expected:** uncommitted modifications to the files listed in the dispatch (env
/ config / bin / docker-compose / docs) plus untracked `bin/test`. No unrelated
drift.

### 1. Bring services up cleanly

```bash
docker compose down
docker compose up -d postgres redis meilisearch
docker compose ps
```

**Expected:** all three services report `(healthy)` after a few seconds.
Container names: `pito-postgres-1`, `pito-redis-1`, `pito-meilisearch-1`.

### 2. Volume audit

```bash
docker volume ls | grep pito
```

**Expected output (exactly these three lines, plus possibly the two unmounted
`pito-notes` / `pito-assets` if you've touched them):**

```
local     pito-meilisearch-data
local     pito-postgres-data
local     pito-redis-data
```

If you see legacy `pito_pito-postgres-data` (or `postgres_data` / `redis_data`
without a prefix), the rename didn't take. Stop and report.

### 3. Boot the dev stack

```bash
bin/dev
```

**Expected:** foreman starts web on `127.0.0.1:3027`, mcp on `127.0.0.1:3028`,
Sidekiq attaches, Tailwind watcher runs, cloudflared tunnel comes up. No
`address already in use` errors.

In another shell, sanity-check the bindings while `bin/dev` runs:

```bash
ss -ltn | grep -E ':3027|:3028|:54327|:64527|:7727'
```

All five should show `127.0.0.1:` (not `0.0.0.0:`).

### 4. Optional — open the tunnel-fronted URLs

If your `~/.cloudflared/config.yml` already points
`app.pitomd.com → http://127.0.0.1:3027` and
`mcp.pitomd.com → http://127.0.0.1:3028` (per the new `docs/setup.md` section),
open `https://app.pitomd.com/` in a browser. Otherwise hit
`http://127.0.0.1:3027/` directly.

**Expected:** dashboard renders normally — no functional change from the port
move, only the listening-port shifted.

### 5. Provision parallel test DBs and confirm the cap

```bash
bin/parallel_setup
```

**Expected:** "Database 'pito_test' already exists" (or "Created database
'pito_test'") for each of `pito_test`, `pito_test2` … `pito_test8`. Then:

```bash
PGPASSWORD=pito psql -h 127.0.0.1 -p 54327 -U pito -lqt \
  | awk -F'|' '{gsub(/ /,"",$1); print $1}' \
  | grep -E '^pito_test'
```

**Expected:** exactly 8 lines — `pito_test` through `pito_test8`. No
`pito_test9`, `pito_test10`, etc.

### 6. Run the full suite via the new wrapper

```bash
bin/test spec/
```

**Expected:** `1059 examples, 0 failures` after ~30 s of warmup + ~10 s of
parallel work. The wrapper exports `PARALLEL_TEST_PROCESSORS=8` and execs
`parallel_rspec`. (This was the value at review time; if you've added specs
since then the count may be slightly higher.)

### 7. Optional — single-file smoke

```bash
bin/test spec/jobs/notes/embed_job_spec.rb
```

**Expected:** the spec file runs, all examples pass. Confirms the wrapper routes
a subset to `parallel_rspec` cleanly. (This file's only diff was a WebMock URL
update from `127.0.0.1:7700` to `127.0.0.1:7727`, so it directly exercises the
port move.)

### 8. Tear down

Stop `bin/dev` with Ctrl+C in its terminal. Then:

```bash
docker compose down
```

**Expected:** containers stop cleanly. Volumes persist (the `pito-postgres-data`
volume keeps your dev data across reboots).

## Cleanup (only if you want a clean retry)

If you want to restart from scratch — for instance, to validate that a fresh dev
host gets the new volume names directly:

```bash
docker compose down --volumes
docker volume rm pito-postgres-data pito-redis-data pito-meilisearch-data
docker compose up -d postgres redis meilisearch
bin/rails db:create db:schema:load db:seed
bin/parallel_setup
```

Note: this is destructive — it wipes your dev database, your Sidekiq queue
state, and your Meilisearch indexes. Don't run it unless you mean it.

## User Validation

This bundle is infrastructure-only — no UI changes — so most validation is
through `bin/dev` running and pages rendering, not new visual surfaces.

[ ] 1. **Side-by-side coexistence.** With `bin/dev` running on pito (web
on 3027) and your fepra2-api dev stack also up (web on 3018), open both project
URLs in two browser tabs (pito's `https://app.pitomd.com/` or
`http://127.0.0.1:3027/`, and fepra2's local URL). Both render their respective
dashboards without one stealing the other's port. No `EADDRINUSE` / "site can't
be reached" on either.

[ ] 2. **Tunnel still works.** Open `https://app.pitomd.com/` — the cloudflared
tunnel on the dev host now forwards `app.pitomd.com` to `http://127.0.0.1:3027`
per the updated config. Page loads normally and shows the pito dashboard.
(Marker check: the URL bar reads `app.pitomd.com`, not `127.0.0.1`.)

[ ] 3. **MCP HTTP endpoint reachable.** Visit `https://mcp.pitomd.com/` (or
whatever path your tunnel routes to) — you should see the MCP server respond. A
bare `GET /` typically returns the MCP info / error JSON; the point is
"Cloudflare → 3028 → Puma → MCP rack app" is wired through. No `502 Bad Gateway`
from Cloudflare.

[ ] 4. **A workspace page renders.** Visit `/dashboard` (or `/channels`) through
the tunnel URL. It should render exactly as before this bundle landed — the port
move is invisible to the user. Pane layout, top nav, and theme are unchanged.

[ ] 5. **No new console / flash errors.** Open the browser devtools, reload the
page once. No JS errors related to ports or hostnames. No flash banners about
misconfiguration.

[ ] 6. **Final architect-commit confirmation checklist.** Before the architect
commits, tick each: - [ ] All 8 Postgres test DBs created (`pito_test` …
`pito_test8`). - [ ] `bin/test spec/` reports `1059 examples, 0 failures`. - [ ]
`docker volume ls | grep pito` returns only the three single-prefix names (no
`pito_pito-...` doubled form, no unprefixed `postgres_data` / `redis_data`). - [
] `app.pitomd.com` and `mcp.pitomd.com` both resolve through the tunnel. - [ ]
`lsof` / `ss` shows pito on `:3027` / `:3028` and (if running) fepra2-api on
`:3018` — no overlap. - [ ] None of the non-blocking concerns above worry you
enough to gate the commit. (If concern #1, the `MEILI_PORT` vs
`MEILISEARCH_PORT` doc/code mismatch, bothers you, ask the architect to dispatch
a one-line follow-up either to compose or to `docs/setup.md` before the commit.)
