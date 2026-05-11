# 24d — `DeleteChannelDataJob` cascade

## Goal

Ship the Sidekiq job that cascades a channel revoke. Given
`(channel_id, youtube_connection_id)`, the job destroys the channel and every
record that depends on it (videos, analytics rows, diffs, change-logs, links,
rejected-imports, calendar entries), then — only if the captured connection now
has zero remaining channels AND zero remaining videos referencing it — destroys
the `YoutubeConnection` itself. The job is idempotent: re-running on an
already-gone channel is a no-op; the YoutubeConnection cleanup re-checks state
at execute time, so a missed branch on the first run gets caught on a manual
retry.

The job exists so the user-facing `[confirm revoke]` flow returns instantly
(redirect + flash) while the destructive work happens asynchronously, and so the
MCP / CLI channel-delete paths can reuse the same cascade contract.

## Files touched

### Job

- `app/jobs/delete_channel_data_job.rb` — NEW. Flat name (matches the existing
  `ChannelSync` job convention, see `app/jobs/channel_sync.rb`).

  ```
  class DeleteChannelDataJob
    include Sidekiq::Job

    sidekiq_options retry: 3, queue: :default

    def perform(channel_id, connection_id_snapshot)
      channel = Channel.find_by(id: channel_id)
      if channel
        connection_id_snapshot ||= channel.youtube_connection_id
        # Rails-side dependent: directives on Channel already cascade
        # most of the dependent tables. We rely on those for correctness
        # and add explicit clears for any FK that uses :nullify (e.g.
        # YoutubeConnection's videos has_many uses :nullify, which the
        # channel destroy would otherwise leave dangling).
        channel.destroy!
      end

      cleanup_orphan_connection(connection_id_snapshot) if connection_id_snapshot
    end

    private

    def cleanup_orphan_connection(connection_id)
      connection = YoutubeConnection.find_by(id: connection_id)
      return unless connection
      return if connection.channels.exists?
      return if connection.videos.exists?

      connection.destroy!
    end
  end
  ```

  The body above is an illustrative shape, not the final code — the spec is
  enforced by the test suite below. Implementation may differ as long as the
  acceptance items pass.

### Routes / controllers

- None. The job is invoked from sub-spec 24c (`ChannelRevokesController#create`)
  and sub-spec 24e (`Channels::BulkRevokesController#create`).

### Specs

- `spec/jobs/delete_channel_data_job_spec.rb` — NEW. Covers:

  **Happy path — full cascade:**
  - Build a Channel with: 3 videos, each with rows in every `video_*` analytics
    table (`video_dailies`, `video_daily_by_countries`,
    `video_daily_by_device_types`, `video_daily_by_operating_systems`,
    `video_daily_by_traffic_sources`, `video_daily_by_subscribed_statuses`,
    `video_daily_by_age_group_genders`, `video_window_summaries`,
    `video_retentions`), plus `video_change_logs`, `video_diffs`,
    `video_game_links`, `calendar_entries`. Build the channel-level cousins:
    `channel_dailies`, `channel_window_summaries`, `top_videos_windows`,
    `channel_change_logs`, `channel_diffs`, `rejected_video_imports`,
    `calendar_entries` for the channel itself.
  - Enqueue the job, run it.
  - Assert: the Channel row is gone; all Video rows are gone; every analytics
    table has zero rows referencing the channel or its videos; `channel_diffs`,
    `video_diffs`, `channel_change_logs`, `video_change_logs`,
    `video_game_links`, `rejected_video_imports`, `calendar_entries` are all
    zero. (One assert per table — explicit, no looping shortcuts; if a future
    table is added without a cascade, the spec must visibly fail on the missing
    assertion.)

  **YoutubeConnection cleanup branches:**
  - Connection with one channel + that channel revoked → connection is
    destroyed.
  - Connection with two channels + one channel revoked → connection survives.
  - Connection with one channel + N orphan videos (channel destroyed, videos
    nullified) → connection survives BECAUSE videos still reference it (the
    second guard). Then explicitly destroying the orphan videos and re-running
    the job → connection now destroyed.
  - Channel with `youtube_connection_id: nil` → no YoutubeConnection operation
    attempted; no error raised.

  **Idempotency:**
  - Run the job twice for the same channel — the second run is a no-op (no
    error, no spurious YoutubeConnection destroy if the cleanup branch already
    fired).
  - Run the job with a `channel_id` that does not exist — no error; the
    YoutubeConnection cleanup branch still runs against the
    `connection_id_snapshot` if provided.

  **Other channels untouched:**
  - Two channels under the same connection. Revoke channel A. Assert: channel B
    and all of B's videos, analytics, diffs, etc. are untouched. Connection
    survives.

  **No orphaned rows:**
  - After a full revoke, sweep every table that has an FK to the channel or its
    videos and assert `Model.where(channel_id: <gone>).count == 0` and
    `Model.where(video_id: <gone>).count == 0` for each cascade target. The
    sweep is enumerated explicitly (no `descendants` magic) so a new table
    forgotten in the cascade fails the test loud.

  **Args contract:**
  - Job accepts `(channel_id, connection_id_snapshot)` in that order.
  - Job accepts `(channel_id, nil)` and reads the connection id from the channel
    record itself before destroy (covers the case where the caller didn't
    snapshot it).

- `spec/jobs/delete_channel_data_job_isolation_spec.rb` (optional, separate file
  for read clarity) — covers the "other channels untouched" isolation cases when
  the suite is dense; keep merged into the main job spec if the file stays
  compact.

### Existing-model audit

- Confirm `Channel`'s existing `has_many` directives use `dependent:` values
  that cascade the right way:
  - `videos: :destroy` ✓
  - `playlists: :destroy` ✓
  - `video_uploads: :destroy` ✓
  - `import_jobs: :destroy` ✓
  - `rejected_video_imports: :destroy` ✓
  - `channel_change_logs: :delete_all` ✓
  - `channel_diffs: :destroy` ✓
  - `calendar_entries: :destroy` ✓
  - `channel_dailies: :delete_all` ✓
  - `channel_window_summaries: :delete_all` ✓
  - `top_videos_windows: :delete_all` ✓

  And `Video`'s:
  - `video_stats: :destroy` ✓
  - `playlist_videos: :destroy` ✓
  - `video_change_logs: :delete_all` ✓
  - `video_diffs: :destroy` ✓
  - `video_dailies` + 6 more `video_daily_*`: `:delete_all` ✓
  - `video_window_summaries: :delete_all` ✓
  - `video_retentions: :delete_all` ✓
  - `calendar_entries: :destroy` ✓
  - `video_game_links: :destroy` ✓

  If any cascade is missing, the job's manual-sweep section must compensate. The
  job spec asserts zero remaining rows in every cascade target — that's the
  canonical fence against drift.

### MCP integration check (optional, raise as follow-up if work needed)

- Audit `app/lib/mcp/tools/delete_records.rb` (or the equivalent path) to
  confirm the channel-delete branch routes through `DeleteChannelDataJob`. If it
  does not (i.e. it calls `channel.destroy!` directly), the cascade still works
  (Rails-side `dependent:` directives handle the data tree), but the
  YoutubeConnection-orphan check is skipped. Two options:
  1. Wire the MCP path through the job — preferred for consistency.
  2. Document the gap under `docs/orchestration/follow-ups.md` and revisit in a
     later sweep.

  Architect recommendation: option 1. Add it to this sub-spec's checkbox list if
  the audit reveals the gap.

## Acceptance

- [ ] `app/jobs/delete_channel_data_job.rb` exists; flat-name convention
      matching `ChannelSync`.
- [ ] Job is `include Sidekiq::Job` with
      `sidekiq_options retry: 3,     queue: :default`.
- [ ] Job accepts `(channel_id, connection_id_snapshot)` and runs to completion
      when either or both are present.
- [ ] Full cascade verified by spec: Channel + all Videos + every analytics
      table + change-logs + diffs + links + rejected-imports + calendar entries
      reach zero rows for the channel.
- [ ] YoutubeConnection is destroyed iff it has zero remaining channels AND zero
      remaining videos. Verified by all four branches in the spec.
- [ ] Idempotency: second run is a no-op (no error, no spurious destroy).
- [ ] Other channels under the same connection are untouched.
- [ ] No orphaned rows after a full revoke (asserted by per-table sweep in the
      spec).
- [ ] The MCP `delete_records` channel branch routes through this job (OR a
      follow-up is filed if the wire-up is deferred).
- [ ] Brakeman / bundler-audit clean.

## Manual test recipe

1. `bin/dev` (Sidekiq is alive).
2. Set up a test channel: `bin/rails console` →
   `Channel.create!(channel_url: "https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx", youtube_connection_id: YoutubeConnection.first.id)`
   (or use a seed channel).
3. Capture the channel id and connection id:
   `c = Channel.last; cid = c.id; conn = c.youtube_connection_id`.
4. Enqueue the job manually: `DeleteChannelDataJob.perform_async(cid, conn)`.
5. Wait a few seconds. In `bin/rails console`:
   - `Channel.find_by(id: cid)` → `nil`.
   - `Video.where(channel_id: cid).count` → `0`.
   - For each analytics table: `VideoDaily.where(channel_id: cid).count` → `0`
     (and so on through the 12 analytics tables enumerated in the spec).
6. Check the YoutubeConnection:
   - If this was the connection's last channel and there are no orphan videos:
     `YoutubeConnection.find_by(id: conn)` → `nil`.
   - Otherwise: connection still present, surviving channels / videos untouched.

Teardown: re-seed via `bin/setup` to repeat the test on a fresh state.

## Cross-stack scope

- **Rails web:** in scope (job definition + spec + optional MCP wire-up).
- **MCP:** in scope only for the audit + optional wire-up to route
  `delete_records[channel]` through the job. If wired, MCP spec updated.
- **CLI:** not in scope. The CLI's channel-delete path is unchanged; it hits
  `/deletions/channel/:ids`, which goes through `DeletionsController`, which
  already calls `channel.destroy` — the Rails-side `dependent:` directives
  handle the cascade. The YoutubeConnection orphan-check is not currently
  performed on that path. Architect recommendation: route `DeletionsController`
  channel branch through the job too, OR file a follow-up. Surface for user.
- **Website:** not in scope.

## Open questions

1. Should `DeletionsController#destroy_channel` also route through
   `DeleteChannelDataJob`? Doing so makes the cascade contract single- sourced
   (web + MCP + CLI all go through the same job). The downside: the user-facing
   delete on `/deletions/channel/:id` becomes async (the action-screen redirect
   happens before the cascade finishes), which is a visible behavior change.
   Architect recommendation: defer to a separate follow-up so this phase ships
   clean. Surface for user.
2. Sidekiq retry policy: `retry: 3` is the architect's default. Is that right
   for a destructive job? An alternative is `retry: false` — the job either
   succeeds on first try or stops loud so the user knows. Architect
   recommendation: `retry: 3` because the destructive ops are idempotent
   (re-running cleans up partial state); a transient DB blip should not leave
   the channel half-revoked.
3. Should the job emit an audit log line for posterity? Architect
   recommendation: no per the umbrella's locked decision #7 (the channel is
   gone; there's nothing to attach an audit row to). The Sidekiq job log serves
   as the trail.
4. The connection's videos `dependent: :nullify` means a channel destroy leaves
   orphan videos pointing at the connection. The job's second guard
   (`return if connection.videos.exists?`) correctly preserves the connection in
   that case. But: are orphan videos with `channel_id` = gone but
   `youtube_connection_id` set the right state to leave in the DB? Architect:
   yes — the existing schema design (per Phase 7C disconnect- lifecycle
   decision) intentionally lets videos outlive their channel. This sub-spec
   inherits that design. Confirm.
