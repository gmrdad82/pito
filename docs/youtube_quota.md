# YouTube API Quota

Reference for how Pito spends its YouTube API quota and why the design choices
in Phase 7 (`Youtube::Client`, `Youtube::PublicClient`, the `youtube_api_calls`
audit table, the per-identity daily budget) sit where they do. Read this
alongside `docs/architecture.md` → "Google OAuth + YouTube API foundation (Phase
7)" and the Phase 7 plan at
`docs/plans/beta/07-google-oauth-youtube-foundation/plan.md`.

## The budget

Every Google Cloud project gets a default daily YouTube API quota of **10,000
units**. Quota is shared across:

- YouTube Data API v3 — both OAuth-authenticated calls and API-key-authenticated
  calls.
- YouTube Analytics API v2 — OAuth-only.

The budget resets at midnight Pacific Time. It is per-project, not per-user and
not per-identity.

Pito's project is shared by every `GoogleIdentity` in the tenant plus every
`Youtube::PublicClient` call. The 10,000-unit budget covers the full surface.

## Cost table

The endpoints Pito uses today (Phase 7) and tomorrow (Phase 8) are all in this
list. Costs are documented by Google and may change without notice; treat the
numbers as a stable approximation, not a contract.

| Endpoint                  | Cost per call | Notes                                                                       |
| ------------------------- | ------------- | --------------------------------------------------------------------------- |
| `videos.list`             | 1 unit        | Up to 50 video IDs per call. Bulk-fetch by id.                              |
| `channels.list`           | 1 unit        | Up to 50 channel IDs per call.                                              |
| `playlistItems.list`      | 1 unit        | Up to 50 items per page. Walk pages for full uploads playlist.              |
| `search.list`             | **100 units** | Avoid. See "search.list is forbidden in normal flows" below.                |
| YouTube Analytics queries | ~1 unit       | Most reports cost 1 unit. Some advanced reports cost more — check per-call. |

Caching note: every call ALSO writes one row to `youtube_api_calls` with the
declared `quota_cost`. The cost is recorded per-call, not derived later from a
table inside Pito — if Google changes the cost of an endpoint, the change takes
effect when `Youtube::Client` is updated, not retroactively.

## Per-identity quota tracking (decision 7.5)

The 10,000-unit project budget is shared, but Pito tracks usage **per identity
per day** so a future multi-user tenant can attribute and reason about its own
slice. The check is:

```
remaining = 10_000 - YoutubeApiCall
                       .where(google_identity_id: identity.id,
                              created_at: today_pacific_range)
                       .sum(:quota_cost)
```

Before every call, `Youtube::Client` computes `estimated_cost` (from the
endpoint cost table above), compares to `remaining`, and either proceeds or
raises `Youtube::QuotaExhaustedError`. Tracked-content calls via
`Youtube::PublicClient` (Phase 8) do not have an identity; their accounting
strategy is the second half of decision 7.5's follow-up — see "Public-key
tracking" below.

## Burst handling — fail-fast (decision 7.6)

When `QuotaExhaustedError` raises, the client does **not**:

- Retry.
- Back off and re-attempt.
- Queue the call for later in the day.
- Fall back to a cheaper endpoint.

It raises, the caller surfaces the error, and the user sees that today's budget
is gone. Retry, backoff, queueing, and graceful degradation are explicit Phase 8
work — they require sync-job orchestration that does not exist yet. Failing fast
in Phase 7 keeps the contract narrow and the debugging story obvious: a quota
error is a quota error, not a tangle of retries papering over one.

## Public-key (unauthenticated) tracking — Phase 8 (decision 7.7)

`Youtube::PublicClient` calls do not have a `GoogleIdentity` to attribute to.
Decision 7.7 defers the accounting model to Phase 8: either
`google_identity_id IS NULL` rows in `youtube_api_calls` are summed against a
separate "public" budget, or a virtual sentinel identity is introduced. Either
way, public calls are still recorded in the audit table from day one (Phase 7
ships the column nullable), so when Phase 8 lands the historical data is already
there to budget against.

## 7-day refresh-token TTL in Testing mode

Google issues refresh tokens that expire after 7 days when the OAuth consent
screen is in **Testing** mode (the mode Pito ships in for the foreseeable future
— see `docs/setup.md` "OAuth consent screen" for why publishing the consent
screen is not worth the verification process for sole-user use). In practice
this is irrelevant: Pito syncs regularly, the access token refreshes within its
1-hour lifetime, and the refresh token gets re-issued long before the 7-day
window closes. The `needs_reauth` flag exists to handle the edge case where the
laptop sits closed for two weeks — the user clicks `[ reconnect ]` and re-walks
the consent screen.

## When to request a quota increase

The 10,000-unit default is comfortably sufficient for a sole user with a
moderate tracked footprint. Sample math:

- 100 tracked videos × 1 daily refresh via `videos.list` (50 IDs per call) = **2
  units/day**.
- 20 owned channels × 1 daily refresh via `channels.list` + 1
  `playlistItems.list` page = **40 units/day**.
- 20 owned channels × 1 daily Analytics report = **20 units/day**.
- Total: ~62 units/day against a 10,000-unit budget. **0.6% utilization.**

The budget gets uncomfortable only at scale: multi-user tenants, sustained
traffic, or operations that hit `search.list` (see below). Request a quota
increase from Google Cloud only when:

- A multi-user phase ships (Theta) and aggregate usage approaches 50% of the
  daily budget on a typical day, OR
- A new operation in a future phase requires `search.list` or other high-cost
  endpoints in normal flows (the bar is high — see below).

The increase request goes through Google Cloud Console → Quotas; Google
typically asks for a usage history (which `youtube_api_calls` provides directly)
and a justification.

## Practical implications for Phase 8

Phase 8 (YouTube Data Sync) is the first phase to actually exercise the client
tier under real load. Three rules carry forward from this document:

- **Tracked content uses `Youtube::PublicClient`.** API key, no identity, no
  Analytics. Channels and videos the user follows but does not own go through
  this path.
- **Owned content uses `Youtube::Client`.** OAuth-authenticated, full Analytics
  access. Channels and videos linked to a `GoogleIdentity`.
- **Sync schedules respect the daily budget.** Per-record sync intervals are
  chosen so the daily roll-up across all tracked + owned records stays well
  under 10,000 units.

### `search.list` is forbidden in normal flows

`search.list` costs 100 units per call — 100x the cost of `videos.list`. A
single page of search results burns 1% of the daily budget; a "discover by
typing a channel name" UX would empty the budget in 100 typing sessions.

Pito's UX is therefore built around **pasted URLs**, not search. The user adds a
tracked channel by pasting `https://www.youtube.com/channel/UC...`, not by
typing a name. Phase 8's add-channel flow validates and parses the URL; it never
calls `search.list` to resolve a name to an id.

Future phases may surface `search.list` in narrow, explicitly user-initiated
contexts (e.g., a one-shot "find this channel" lookup that the user knows costs
more), but the default flows do not call it.
