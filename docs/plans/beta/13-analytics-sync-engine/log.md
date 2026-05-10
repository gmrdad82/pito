# Phase 13 — Analytics Sync Engine + Tables + Dashboard

> **Status:** specs in flight as of 2026-05-10. No implementation yet. Phase
> folder created during the architect-spec dispatch that wrote the three specs
> under `specs/`.

## Plan

Per realignment work unit 5 + Mobile note 3
(`docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md`). Big work
unit; split into three specs landing in this order:

1. `specs/01-analytics-data-model.md` — schema for every analytics table
   enumerated in Note 3. Migrations only. No API client. No views.
2. `specs/02-analytics-sync-engine.md` — Sidekiq orchestrator + per-channel /
   per-video child jobs + `Youtube::AnalyticsClient` wrapper around
   `google-apis-youtube_analytics_v2` + retry/backoff + token-expiry + backfill
   mode + sidekiq-cron schedule. Builds on spec 01.
3. `specs/03-analytics-dashboard.md` — Hotwire / Chartkick views for every
   dashboard surface enumerated in Note 3. Builds on specs 01 + 02.

## Cross-references

- `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — source of
  truth for the data model + query shapes.
- `docs/realignment-2026-05-09.md` — work unit 5 ("Analytics sync engine
  - tables + dashboard"); marked "very big — split into sub-units."
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
  `tenant_id` on any analytics table.
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
  `YoutubeConnection` is the OAuth grant holder used by the sync engine.
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — Phase 8 prerequisite (analytics tables shed `tenant_id`).
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  — Phase 9 prerequisite (`YoutubeConnection` rename).
- `docs/plans/beta/12-video-schema-expansion/` — Phase 12 prerequisite (Video
  schema with `youtube_video_id`, `published_at`, `category_id`, `duration`,
  `tags`).

## Sessions

### 2026-05-10 — rails-impl: Spec 01 (analytics data model) lands

**Spec:** `specs/01-analytics-data-model.md`. **Outcome:** schema-only
implementation complete and green. Specs 02 (sync engine) and 03
(dashboard) deferred to a separate dispatch — see "Open follow-ups"
below.

**Note on commit lineage.** The Spec-01 files (12 models, 12 factories,
13 specs, 1 migration, the 2 has-many additions on Channel + Video)
landed in commit `6391f12 Fix Turbo Frame mismatch on bulk actions
across 5 list surfaces` on 2026-05-10 16:04 UTC+2 — bundled into a
larger commit that also covered Phase 14 Spec 02 (bundles) and other
phase-in-flight work. This session re-implemented the Spec-01 lane
end-to-end against a clean tree and confirmed every file matches main
byte-for-byte (`git diff HEAD app/models/channel_daily.rb …` empty for
every Spec-01 file). The implementation contract is unchanged from
what `main` already shipped; this session's net diff is the log entry
below.

**Files added (analytics models, schema, factories, specs):**

- `db/migrate/20260510155554_create_analytics_tables.rb` — single
  migration creating the `analytics_window` Postgres enum + 12
  analytics tables (`channel_dailies`, `video_dailies`, six sliced
  `video_daily_by_*` tables, `channel_window_summaries`,
  `video_window_summaries`, `top_videos_windows`, `video_retentions`).
- `app/models/channel_daily.rb`, `app/models/video_daily.rb`, six
  `app/models/video_daily_by_*.rb` files,
  `app/models/channel_window_summary.rb`,
  `app/models/video_window_summary.rb`,
  `app/models/top_videos_window.rb`, `app/models/video_retention.rb`
  — 12 new model files.
- `spec/factories/{channel_dailies,video_dailies,video_daily_by_countries,video_daily_by_device_types,video_daily_by_operating_systems,video_daily_by_traffic_sources,video_daily_by_subscribed_statuses,video_daily_by_age_group_genders,channel_window_summaries,video_window_summaries,top_videos_windows,video_retentions}.rb`
  — 12 new factory files.
- `spec/models/{channel_daily,video_daily,video_daily_by_country,video_daily_by_device_type,video_daily_by_operating_system,video_daily_by_traffic_source,video_daily_by_subscribed_status,video_daily_by_age_group_gender,channel_window_summary,video_window_summary,top_videos_window,video_retention,analytics_associations}_spec.rb`
  — 13 model specs.
- `spec/db/analytics_schema_spec.rb` — schema integrity spec
  (Postgres enum existence, UNIQUE composite indexes on natural keys,
  ON DELETE CASCADE on FKs to `channels` / `videos`, no `tenant_id`
  columns, ratio-column scale `numeric(10, 6)`, duration-column scale
  `numeric(10, 2)`).

**Files edited:**

- `app/models/channel.rb` — added `has_many :channel_dailies`,
  `:channel_window_summaries`, `:top_videos_windows`, all
  `dependent: :delete_all`.
- `app/models/video.rb` — added `has_many` for the eight per-video
  analytics relations and `:video_window_summaries`,
  `:video_retentions`, all `dependent: :delete_all`.
- `db/schema.rb` — auto-regenerated to include the 12 new tables and
  the `analytics_window` enum.

**Architectural decisions honored verbatim from the spec's Master agent
decisions block:**

1. `creator_content_type` slice — deferred (not added).
2. Tables use Rails-pluralized inflector form (`channel_dailies`,
   `video_dailies`, etc.).
3. No CHECK constraint on monetization columns (app-level
   `MONETIZATION_ENABLED` flag is the gate; Spec 02 owns).
4. Single migration with `execute("CREATE TYPE analytics_window AS
   ENUM (...);")` at the top — Rails 8.1 captured the enum in
   `schema.rb` cleanly via `create_enum`.
5. Cascade order: ON DELETE CASCADE on every FK + Rails-level
   `dependent: :delete_all` declarations as belt-and-suspenders.
6. Active-video classification: no schema column; pure derived
   predicate (Spec 02 owns).

**Notable implementation choices:**

- `*_window_summary` and `top_videos_windows` use the
  `analytics_window` Postgres enum directly via `t.column :window,
  :analytics_window`. Rails' built-in `enum :window` macro is NOT
  used because that macro expects an integer column; the value is
  stored as the string itself. Rails-side validation of the four
  values uses `validates :window, inclusion: { in: WINDOWS }`. An
  out-of-range value (e.g., `"bogus"`) is rejected by Postgres at
  the wire level — `ActiveRecord::StatementInvalid` is raised before
  the row reaches the table. Specs assert this.
- `video_retentions` omits `created_at` / `updated_at` per spec; the
  model sets `self.record_timestamps = false` and a
  `before_validation :stamp_computed_at` callback lazily populates
  `computed_at` if the caller hasn't already.
- `top_videos_windows` rank-uniqueness validation is
  custom-implemented because Rails' built-in `validates :rank,
  uniqueness: { scope: %i[channel_id window] }` would shadow the
  primary natural-key uniqueness on `(channel_id, window, video_id)`.
  Two named uniqueness validations let the model's `valid?` method
  surface either violation correctly.
- The sliced daily tables' UNIQUE indexes were given short names
  (`idx_video_daily_by_country_uniq`, etc.) because the auto-generated
  names collide with Postgres' 63-character limit.

**Test sweep:**

- Spec 01 enumerated 113 test cases across 14 spec files. The
  implementation landed 118 atomic test cases across 14 spec files
  (the small surplus reflects natural test grouping — a couple of
  enumerated cases expanded into 2 atomic `it` blocks). All 118 pass.
- Full RSpec suite: 3158 examples, 7 failures, 1 pending. The 7
  failures are pre-existing on `main` (bundles, games, calendar,
  composites — unrelated phase-in-flight work). No analytics spec
  fails; no Channel / Video spec broken by the additive `has_many`
  declarations.

**Quality gates:**

- `bundle exec rspec spec/models/{channel_daily,video_daily,…} spec/db/analytics_schema_spec.rb spec/models/analytics_associations_spec.rb`
  → 118 examples, 0 failures.
- `bundle exec rubocop` over the 41 changed/new files → 41 files
  inspected, no offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

**Reviewer checkpoints (from Spec 01) covered:**

1. ✅ `git grep 'tenant_id' db/migrate/20260510155554_create_analytics_tables.rb`
   → zero matches.
2. ✅ `bin/rails db:migrate` succeeds (already exercised in dev + test).
3. ✅ Model unit specs green.
4. ✅ `spec/db/analytics_schema_spec.rb` green.
5. ✅ `spec/models/analytics_associations_spec.rb` green.
6. ✅ Full RSpec suite no analytics-related regressions.
7. ✅ Rubocop clean.
8. ✅ Brakeman clean.
9. ⏳ Manual playbook §1-§9 — pending user validation.

**Open follow-ups for next dispatch:**

- **Spec 02 (analytics-sync-engine.md) — DEFERRED.** ~139 enumerated
  test cases. Touches `app/jobs/`, `app/services/youtube/`,
  `app/services/backfill/`, `config/sidekiq*.yml`, `db/seeds.rb`,
  plus the ~10 spec files. Note: the existing
  `app/models/youtube_api_call.rb` has `CLIENT_KINDS = %w[oauth
  public]` and a fixed `OUTCOMES` whitelist — Spec 02 must extend
  these (`analytics_v2` kind, `succeeded` / `auth_failed` /
  `rate_limited` / `failed` outcomes). The existing fixture also
  uses `success` rather than `succeeded`; reconcile with the
  master-agent copy decision (`youtube_analytics.query.succeeded`)
  during the Spec 02 dispatch.
- **Spec 03 (analytics-dashboard.md) — DEFERRED.** ~118 enumerated
  test cases. Routes, controllers, views, helpers, decorators,
  Stimulus controllers. Depends on Spec 02 having populated tables
  for system-spec coverage.
- **Channel-level slice tables (C4 / C5).** Per spec 02 master-agent
  decision, deferred entirely; query-time rollup in Spec 03.
- **Documentation updates.** `docs/architecture.md` and `CLAUDE.md`
  edits called out by Spec 01's "Files touched → Documentation"
  block — dispatched separately to docs-keeper, not part of this
  rails-impl session.
