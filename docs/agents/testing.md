# testing — project-specific conventions

Standing context for any agent that runs the RSpec suite — implementation agents
proving their own coverage, verification agents establishing a baseline. Read
this once; dispatch prompts no longer re-paste it.

## Running the suite — use parallel

- The repo has `parallel_tests` (5.7.0) installed; `config/database.yml` is
  wired for it via the `TEST_ENV_NUMBER` suffix.
- Standard full-suite run: `bundle exec parallel_rspec spec/ -n 8`.
- **8 processes maximum.** The machine has 20 cores but the user explicitly
  capped suite runs at 8 — do not exceed.
- Single-process `bundle exec rspec <files>` is only for a targeted handful of
  files (one feature's spec set, a quick re-check). Never the whole suite.

## Parallel DB setup

- Before a first parallel run, or after any schema change:
  `bundle exec rake parallel:create parallel:prepare`.
- This creates `pito_test` through `pito_test8` and loads the current
  `db/schema.rb` into each.
- Parallel DBs from a prior run may carry a stale schema — re-run
  `parallel:prepare` after any migration.

## Known gotcha — `PG::ObjectInUse` on prepare

`parallel:prepare` runs `db:purge`, which fails with `PG::ObjectInUse` if a
stray connection is holding a `pito_test*` database (common after an interrupted
run). Terminate stray connections before prepping:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname LIKE 'pito_test%' AND pid <> pg_backend_pid();
```

Then re-run `bundle exec rake parallel:prepare`.

## Pre-existing baseline failures

There is a standing set of suite failures that predate current work. **Agents
must NOT chase these** — they are out of scope unless a task explicitly targets
them. A clean full-suite run that matches the baseline is a pass.

This list is reconciled after each full-suite verification run; treat the newest
phase log's recorded baseline as authoritative if this differs.

### Current known baseline

Most recent recorded baseline — verification agent run 2026-05-15 01:57
(`/home/catalin/Dev/pito/tmp/verification/baseline-2026-05-15.md`): **6
failures, 1 pending** out of 5580 examples. The example count is reduced vs. the
prior Phase 29 A1 baseline (8587 examples) because the run was narrower in
scope; the failure clusters still map onto the documented standing baseline.

Per-file enumeration for the 2026-05-15 run:

| Failures | Spec file                                           | Examples (line) |
| -------: | --------------------------------------------------- | --------------- |
|        1 | `spec/lint/numeric_formatting_spec.rb`              | :52             |
|        1 | `spec/requests/calendar/month_spec.rb`              | :125            |
|        2 | `spec/requests/composites_spec.rb`                  | :28, :79        |
|        1 | `spec/requests/deletions_spec.rb` (games branch)    | :227            |
|        1 | `spec/requests/settings/oauth_applications_spec.rb` | :47             |

Pending (1): `spec/models/game_calendar_derivation_spec.rb:42` — "Phase 14 IGDB
sync flow not implemented" (explicit pending marker; not a failure).

Cluster mapping (every failing example maps onto the standing baseline cluster
list — composites, calendar, games, OAuth flow / settings panes,
numeric-formatting lint):

| File                                                | Cluster                              |
| --------------------------------------------------- | ------------------------------------ |
| `spec/lint/numeric_formatting_spec.rb`              | numeric-formatting lint              |
| `spec/requests/calendar/month_spec.rb`              | calendar                             |
| `spec/requests/composites_spec.rb`                  | composites                           |
| `spec/requests/deletions_spec.rb` (games branch)    | games                                |
| `spec/requests/settings/oauth_applications_spec.rb` | OAuth flow (Doorkeeper / OAuth apps) |

The `settings/oauth_applications_spec.rb` failure surfaces as a
`PG::ConnectionBad` ("terminating connection due to administrator command")
inside the factory — environmental fallout from the long-running suite, still
squarely in the OAuth-flow / settings-panes cluster the baseline acknowledges.

Standing cluster list (the broader surfaces that absorb intermittent baseline
failures across runs):

- composites
- webhooks
- games
- settings panes (`_slack_pane` / `_discord_pane` view specs — `nav-sep`
  middle-dot assertion)
- calendar
- seeds
- OAuth flow
- tokens
- numeric-formatting lint

Pending reconciliation from the next full-suite verification run — the
2026-05-15 capture above is partial (5580 examples vs. the 8587-example Phase 29
A1 reference); the reviewer's upcoming full parallel run will be the next
authoritative reconciliation, and that enumeration will replace the table above.
Note: Phase 29 Unit A2 left the suite far above baseline (mandatory-2FA gate
fallout, ~88 specs over the documented baseline) — that is tracked as an A2 open
issue, not part of this standing baseline.

## Verify-vs-implement task discipline

- **Verification / baseline tasks are read-only.** The agent runs specs and
  reports — it never edits `app/`, `lib/`, `config/`, or `spec/`. If a fix is
  needed, it STOPs and reports; the master agent dispatches the right
  implementation agent.
- **Implementation tasks own their spec coverage** per the regression-spec
  mandate. Cross-reference `docs/plans/beta/29-screen-polish-sweep/roadmap.md`.
