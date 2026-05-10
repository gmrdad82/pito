# Phase 13 Analytics — Security audit (2026-05-10)

**Branch:** `main`  
**Specs:** `docs/plans/beta/13-analytics-sync-engine/specs/{01,02,03}-*.md`  
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-13-analytics.md`

## Verdict

MERGE WITH FIX-FORWARD. 0 critical/high. 3 medium (all actionable). 3 low. 3
informational.

## Findings

### F1 — AnalyticsClient bypasses ServiceFactory (MEDIUM, regression of Phase 15 F2)

`app/services/youtube/analytics_client.rb:297-301` builds the YouTube Analytics
service inline rather than via
`Youtube::ServiceFactory.analytics_service(@connection)`, defeating the
open/read/write timeouts Phase 15 standardized. A hung Google endpoint wedges a
Sidekiq worker indefinitely, blowing past Sidekiq's 25s shutdown drain.

**Fix:** Route through `Youtube::ServiceFactory.analytics_service`. After the
fix, `Youtube::OauthRefresh#build_oauth_credentials` is dead code — drop it.

### F2 — AnalyticsClient flips `needs_reauth` on first 401 without refresh-retry (MEDIUM, regression of Phase 12 F1)

`app/services/youtube/analytics_client.rb:222-226, 235-241` immediately writes
`needs_reauth: true` on `AuthorizationError` / `ClientError` 401. Mirror
`Youtube::Client:209-226`: attempt one TokenRefresher call + retry; only persist
`needs_reauth: true` if the refresh itself raises NeedsReauthError.

**Impact:** A connection whose access token simply expired between freshness
check and request gets stuck in re-auth state until the user manually
re-authorizes — even though one token refresh would have fixed it.

### F3 — No rate limit on the three analytics refresh POST endpoints (MEDIUM)

`app/controllers/channels/analytics_refresh_controller.rb`,
`app/controllers/videos/analytics_refresh_controller.rb`,
`app/controllers/videos/retention_refresh_controller.rb` — neither covered by
`Rack::Attack` nor by per-resource locks. A held [refresh now] click can fan out
hundreds of jobs in seconds.

**Fix:** Per-resource Redis cache lock inside the controller
(`Rails.cache.write(lock_key, 1, expires_in: 60.seconds, unless_exist: true)`).

### F4 — `analytics:backfill` rake task accepts loose date input (LOW)

`lib/tasks/analytics.rake:25-26` uses `Date.parse`. Replace with `Date.iso8601`
and add a hard cap on range width when reviewer Concern 1 (from/to plumbing)
lands.

### F5 — Per-channel/per-video analytics surfaces don't scope by `Current.user` (LOW, pre-existing pattern)

`Channel.friendly.find` / `Video.friendly.find` is unscoped today. Consistent
with the seeded-singleton model. Document the assumption; tighten when
multi-user data scoping lands.

### F6 — `Youtube::TokenRefresher.post_form` has no HTTP timeouts (LOW, pre-existing)

`app/services/youtube/token_refresher.rb:55-63` — set `http.open_timeout = 10`
and `http.read_timeout = 30` to match ServiceFactory.

## Out-of-scope but noted

- `youtube_video_id` column has no format validator (informational; SDK
  URL-encodes)
- `analytics_window_picker_controller.js` is a no-op marker (reviewer Concern 7)
  — drop or wire
- `Youtube::OauthRefresh#build_oauth_credentials` becomes dead code after F1

## Quality gates

- Brakeman strict: 6 warnings (same 6 as on `main` pre-Phase-13); 0 new
- bundler-audit: clean
- /security-review: no SQL interpolation, no eval/send/constantize, no
  shell-out, no new routes skipping authenticate_session!, no CSP relaxation

## Severity table

| Severity      | Count | IDs           |
| ------------- | ----- | ------------- |
| Critical      | 0     | —             |
| High          | 0     | —             |
| Medium        | 3     | F1, F2, F3    |
| Low           | 3     | F4, F5, F6    |
| Informational | 3     | (notes above) |

## Action

F1 + F2 + F3 fix-forward dispatched 2026-05-10 21:40.
