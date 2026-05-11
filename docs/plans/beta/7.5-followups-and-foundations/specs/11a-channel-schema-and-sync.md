# Phase 7.5 — Step 11a — Channel Schema + Sync Foundation

> Foundation sub-spec for Step 11. Adds every Channel resource column the
> management surface needs, the `channel_change_logs` audit table, and the
> `Video.title` column. Replaces the current `ChannelSync` placeholder with the
> real `Youtube::Client#fetch_channel` path so all subsequent sub-specs
> (11b–11i) have a populated schema to work against.
>
> **Depends on:** Phase 7 (Google OAuth + `Youtube::Client` + audit + quota)
> committed. Path A2 (thin Channel/Video schema) committed.
>
> **Unblocks:** 11b (show page), 11c (edit form), 11d (preview component), 11f
> (banner upload), 11g (change history UI), 11i (daily diff-check). None of them
> can dispatch until 11a's columns + job exist.
>
> **Parent spec:**
> [`11-channel-management-and-preview.md`](./11-channel-management-and-preview.md).

---

## Goal

Land the schema migrations, model additions, `Youtube::Client#fetch_channel`
extension, and `ChannelSync` job rewrite that together turn the current
`last_synced_at`-only placeholder into a real channel-sync foundation. After
this sub-spec ships, calling `ChannelSync.perform_async(channel.id)` on a
connected channel populates every cached column from one `channels.list` API
call.

No UI work here. No edit form. No preview component. Just schema + model +
service + job, plus exhaustive spec coverage.

## Files touched

### Migrations (3)

- `db/migrate/<TS>_add_channel_resource_fields.rb` — adds the following columns
  to `channels`:
  - `title :string`
  - `handle :string`
  - `description :text`
  - `country :string` (limit 2 — ISO 3166-1 alpha-2)
  - `default_language :string` (limit 10 — BCP-47 tag)
  - `keywords :text`
  - `banner_url :string`
  - `avatar_url :string`
  - `watermark_url :string`
  - `watermark_timing :string` — enum-as-string. **NO `watermark_position`
    column** per parent spec D21 (YouTube only supports right-hand corner; image
    evidence + live-API verification).
  - `watermark_offset_ms :integer`
  - `links :jsonb`, default: `[]`, null: false
  - `subscriber_count :bigint`
  - `view_count :bigint`
  - `video_count :integer`
  - `hidden_subscriber_count :boolean`, default: false, null: false
  - `published_at :timestamp`
  - `title_changed_at :timestamp`
  - `handle_changed_at :timestamp`

  Indexes: `index_channels_on_handle` (uniqueness NOT enforced — YouTube handles
  can collide across deleted-then-reused namespaces; uniqueness is YouTube's
  concern). The migration is reversible via `change` blocks (each `add_column`
  reverses cleanly).

- `db/migrate/<TS>_create_channel_change_logs.rb` — new table:
  - `id` (bigint pk)
  - `channel_id` (FK to `channels`, NOT NULL, indexed)
  - `field` (string, NOT NULL — values constrained to `"title"` or `"handle"` by
    a model validator, not a DB check constraint, for portability)
  - `old_value` (string, nullable — null for the first push when no prior value
    exists)
  - `new_value` (string, NOT NULL)
  - `changed_at` (timestamp, NOT NULL, indexed)
  - `changed_by_user_id` (FK to `users`, NOT NULL)
  - `created_at`, `updated_at`

  NO `tenant_id` (single-install + multi-user per ADR 0003). Append-only; no
  UPDATE or DELETE in normal flow.

- `db/migrate/<TS>_add_title_to_videos.rb` — adds `title :string` (nullable) to
  `videos`. Rendered as "untitled" placeholder when nil per parent spec D1.
  NOTE: the live `Video` model in `app/models/video.rb` already declares
  `validates :title, length: { maximum: 100 }` — if the column does not yet
  exist (Phase 7.5 schema state at the time of 11a's dispatch), this migration
  adds it. If a later phase already added it, this migration becomes a no-op and
  the implementation agent reports back rather than silently skipping; the
  parent spec's "Open questions" section is amended.

### Models

- `app/models/channel.rb` — extend with:
  - Validations:
    - `title`: length 1..100 (YouTube's documented max), allow blank
      (display-only until sync populates).
    - `handle`: length 3..30, format `\A@[A-Za-z0-9._-]+\z`, allow blank.
    - `description`: length up to 5000, allow blank.
    - `country`: format `\A[A-Z]{2}\z`, allow blank.
    - `default_language`: format BCP-47-lite (`\A[a-z]{2,3}(-[A-Z]{2})?\z`),
      allow blank.
    - `watermark_timing`: inclusion in
      `%w[always entire_video offset_from_start offset_from_end]`, allow blank.
    - `watermark_offset_ms`: numericality, `greater_than_or_equal_to: 0`, allow
      blank.
    - `links`: custom validator — must be an Array; each entry must be a Hash
      with `title` (1..50) and `url` (matching a strict `\Ahttps?://` regex);
      max 5 entries.
    - `subscriber_count`, `view_count`, `video_count`: numericality,
      `greater_than_or_equal_to: 0`, allow blank.
  - Associations:
    - `has_many :channel_change_logs, dependent: :destroy` (deleting the channel
      deletes its history; the DB FK is also ON DELETE CASCADE).
  - Helpers:
    - `title_locked?` →
      `title_changed_at.present? && title_changed_at > 14.days.ago`.
    - `handle_locked?` → same shape for `handle_changed_at`.
    - `title_unlock_at` → `title_changed_at + 14.days` when locked, else nil.
    - `handle_unlock_at` → same shape for handle.
  - The existing `enqueue_initial_sync` / `enqueue_sync_on_star` after-commit
    hooks stay; 11a does NOT add the connect-transition hook (that's 11c's
    `after_update_commit` on `youtube_connection_id` change, deferred so it
    lands alongside the edit form).

- `app/models/channel_change_log.rb` — new model:
  - `belongs_to :channel`
  - `belongs_to :changed_by_user, class_name: "User"`
  - Validations: `field` inclusion in `%w[title handle]`, presence on
    `new_value`, `changed_at`.
  - Scope: `recent` — `order(changed_at: :desc).limit(20)`.
  - **Append-only enforcement.** Override `update` / `update!` / `destroy` to
    raise `ActiveRecord::ReadOnlyRecord`. Implementation:
    `def readonly?; persisted?; end` is the lowest-friction option; 11a picks
    it.

- `app/models/video.rb` — extend with `title` column awareness. The model
  already declares `validates :title, length: { maximum: 100 }` (see current
  `app/models/video.rb` lines 93–95). If the column does not yet exist when 11a
  dispatches, the migration above adds it; no further model change is needed
  beyond confirming the existing validator still fires post-migration. If the
  column already exists, 11a's model change is a no-op and the implementation
  agent reports.

### Service

- `app/services/youtube/client.rb` — extend with `fetch_channel(channel)`:
  - Calls `channels.list` with
    `mine: true, parts: %i[snippet statistics brandingSettings contentDetails status]`.
  - Quota cost: 1 unit (per `docs/youtube_quota.md`).
  - Audit: routes through the existing `perform("channels.list", "GET")`
    chokepoint so quota + retry + audit semantics are uniform.
  - Returns a normalized Hash:

    ```ruby
    {
      title:                    snippet[:title],
      handle:                   snippet[:custom_url], # @handle when present
      description:              snippet[:description],
      country:                  snippet[:country],
      default_language:         snippet[:default_language],
      keywords:                 branding[:channel][:keywords],
      banner_url:               branding[:image][:banner_external_url],
      avatar_url:               snippet[:thumbnails][:default][:url],
      watermark_url:            nil, # watermarks.set is a separate call
      watermark_timing:         nil, # ditto
      watermark_offset_ms:      nil, # ditto
      links:                    parsed_links_array, # 11c populates fully
      subscriber_count:         stats[:subscriber_count]&.to_i,
      view_count:               stats[:view_count]&.to_i,
      video_count:              stats[:video_count]&.to_i,
      hidden_subscriber_count:  stats[:hidden_subscriber_count] ? true : false,
      published_at:             snippet[:published_at]
    }
    ```

  - On 401 / 429 / 5xx the existing `execute_with_retry` chain handles retry +
    audit + error surfacing; `fetch_channel` only constructs the normalized hash
    on success.
  - No DB writes from inside the service. The caller (`ChannelSync`) persists.

### Job

- `app/jobs/channel_sync.rb` — replace the current placeholder body
  (`channel.update_columns(last_synced_at: Time.current)`) with the real fetch +
  persist path:
  - Loads the channel.
  - Returns early (no-op) if `channel.youtube_connection_id.nil?`.
  - Instantiates `Youtube::Client.new(channel.youtube_connection)`.
  - Calls `client.fetch_channel(channel)`.
  - In a single `Channel.transaction`, calls
    `channel.update!(normalized_hash.merge(last_synced_at: Time.current))`.
  - On `Youtube::NeedsReauthError` / `Youtube::TransientError` /
    `Youtube::QuotaExhaustedError`: log + re-raise so Sidekiq's retry machinery
    picks it up. The audit row is already written by `Youtube::Client#perform`.
  - On `Youtube::PermanentError`: log + DO NOT retry (mark the job failed).
    Sidekiq's `retry: 3` setting handles transient cases; permanent errors
    should not waste retries.

### Specs (mandatory, per spec-pyramid extension D and the standing

"spec exhaustively" directive)

Every file below ships with the implementation; the dispatch is rejected if any
layer is skipped.

- **Migration rollback specs** (one per migration):
  - `spec/migrations/add_channel_resource_fields_spec.rb`
  - `spec/migrations/create_channel_change_logs_spec.rb`
  - `spec/migrations/add_title_to_videos_spec.rb`
  - Each: roll up, assert columns / tables exist with the expected types, roll
    down, assert clean reversal (no leftover columns or tables), roll up again
    to leave the test DB in the post-migration state.

- **Model specs:**
  - `spec/models/channel_spec.rb` (extend existing):
    - Validations: presence / absence / length / format / numericality for every
      new column, happy + sad cases each.
    - `links` validator: empty array (valid), array of valid hashes (valid),
      array exceeding 5 entries (invalid), array with a hash missing `title`
      (invalid), array with a hash missing `url` (invalid), array with an
      invalid url shape (invalid), non-Array input (invalid).
    - Associations: `has_many :channel_change_logs` with `dependent: :destroy`.
      Destroying a channel destroys its logs.
    - `title_locked?` / `handle_locked?` / `title_unlock_at` /
      `handle_unlock_at`: each at the boundary (13d 23h, exactly 14d, 14d 1m) —
      three scenarios apiece.
  - `spec/models/channel_change_log_spec.rb` (new):
    - Validations: `field` inclusion, `new_value` presence, `changed_at`
      presence.
    - Associations: `belongs_to :channel`, `belongs_to :changed_by_user`.
    - `recent` scope: returns last 20 by `changed_at desc`.
    - Append-only: `record.update!(field: "handle")` raises
      `ActiveRecord::ReadOnlyRecord`. `record.destroy` raises
      `ActiveRecord::ReadOnlyRecord` (or the analogous error from the chosen
      mechanism).
  - `spec/models/video_spec.rb` (extend if `title` is newly added by 11a;
    otherwise the existing `length: { maximum: 100 }` specs already cover the
    surface):
    - Title nil → valid (display-only).
    - Title 100 chars → valid.
    - Title 101 chars → invalid.

- **Service specs:**
  - `spec/services/youtube/client_fetch_channel_spec.rb` (new):
    - Happy: WebMock stubs `channels.list` with a full JSON response;
      `fetch_channel(channel)` returns the expected normalized hash with every
      key populated. Audit row written with `endpoint: "channels.list"`,
      `outcome: "success"`, `http_status: 200`.
    - Sad — 401 once then refresh succeeds, second call returns 200: assert one
      refresh, one retry, audit row reflects final success.
    - Sad — 401 after refresh: raises `Youtube::NeedsReauthError`, audit row
      `outcome: "auth_failed"`, `http_status: 401`.
    - Sad — 429 with retry-after: sleeps the retry-after, retries, on second 429
      raises `Youtube::TransientError`, audit row `outcome: "rate_limited"`.
    - Sad — 403 quota exhausted: raises `Youtube::QuotaExhaustedError`, audit
      row `outcome: "quota_exceeded"`.
    - Sad — 5xx three times: raises `Youtube::TransientError` after
      `MAX_5XX_ATTEMPTS`, audit row `outcome: "server_error"`.
    - Edge — minimal snippet (no `country`, no `default_language`, no
      `keywords`, no `banner_url`): returns the hash with `nil` for the missing
      fields; does NOT raise.
    - Edge — `hidden_subscriber_count: true` in the response: normalized hash
      carries `hidden_subscriber_count: true`. Stats `subscriber_count` may be
      absent or "0"; the normalizer doesn't crash.
    - Edge — handle absent (the channel has no `@handle`): normalized hash
      carries `handle: nil`.

- **Job specs:**
  - `spec/jobs/channel_sync_spec.rb` (replace placeholder spec):
    - Happy: channel with `youtube_connection_id` present; stub
      `Youtube::Client#fetch_channel` to return a fully populated hash;
      `ChannelSync.new.perform(channel.id)` updates every column AND stamps
      `last_synced_at`; only ONE transaction is opened.
    - Edge — channel without `youtube_connection_id`: job is a no-op; no API
      call; no DB write; `last_synced_at` unchanged.
    - Edge — channel not found (deleted between enqueue and perform): job is a
      no-op; no raise; no API call. (Mirrors current
      `Channel.find_by(id: channel_id); return unless channel` posture.)
    - Sad — `Youtube::NeedsReauthError` from `fetch_channel`: re-raised so
      Sidekiq retries; no partial DB write (the transaction rolls back);
      `last_synced_at` unchanged.
    - Sad — `Youtube::TransientError`: re-raised; same posture.
    - Sad — `Youtube::QuotaExhaustedError`: re-raised; same posture.
    - Sad — `Youtube::PermanentError`: logged and NOT re-raised (or re-raised as
      a non-retryable error; 11a picks; the spec asserts Sidekiq's retry-count
      does not climb).
    - Sad — `ActiveRecord::RecordInvalid` from `channel.update!` (the service
      returned a value that fails a Channel validator — e.g., a 101-char title
      from a wonky YouTube response): re-raised; transaction rolls back;
      `last_synced_at` unchanged.

- **No request / system / component specs in 11a.** Those land in 11b (show page
  system spec), 11c (edit form request + system), and 11d (preview component).

## Acceptance

- [ ] Three migrations land. Each is reversible. Migration rollback specs pass.
- [ ] `Channel` model adds every column, validator, association, and helper
      listed in "Models" above. Validation specs cover every column happy +
      sad + edge per the spec-pyramid directive.
- [ ] `ChannelChangeLog` model exists with the listed associations, validations,
      scope, and append-only enforcement. Model specs cover every shape.
- [ ] `Video.title` column exists (added by 11a or pre-existing — the
      implementation agent reports either way). The existing `Video#title`
      validators continue to fire post-migration.
- [ ] `Youtube::Client#fetch_channel(channel)` returns the normalized hash shape
      documented above. Service specs cover happy + 401-refresh +
      401-after-refresh + 429 + 403-quota + 5xx + minimal-snippet edge +
      hidden-subscriber-count edge + handle-absent edge.
- [ ] `ChannelSync` job replaces the placeholder with the real fetch + persist
      path. Job specs cover happy + missing-connection + missing- channel +
      needs-reauth + transient + quota + permanent + record-invalid scenarios.
- [ ] `bundle exec rspec` green for every file 11a touches.
- [ ] `bundle exec rubocop` green.
- [ ] No JS `alert` / `confirm` / `prompt`. No `data-turbo-confirm`. (None
      introduced in 11a — schema-only sub-spec — but the gate stays.)
- [ ] No `tenant_id` columns added. No `BelongsToTenant` includes. (Per ADR
      0003.)
- [ ] No external boolean serialization (`yes` / `no`) introduced in 11a — the
      service returns internal Boolean for `hidden_subscriber_count`. Boundary
      conversion (when 11i or future MCP tools expose the value) is the
      consumer's responsibility.
- [ ] `bin/rails db:migrate` runs cleanly against the dev DB after 11a ships
      (per `docs/agents/rails.md` rule F).

## Manual test recipe

This sub-spec adds no UI surface; manual validation is limited to
`rails console`.

### Prereqs

- Phase 7 OAuth identity connected with at least one owned channel.
- Test channel on YouTube the user controls.

### Steps

1. Pull / rebase. `bundle install`. `bin/rails db:migrate` — the three new
   migrations apply cleanly.
2. `bin/rails db:rollback STEP=3` — every migration reverses cleanly with no
   errors.
3. `bin/rails db:migrate` again — back to the post-11a schema.
4. `bin/rails console`.
5. Locate a connected channel:
   ```ruby
   channel = Channel.connected.first
   ```
6. Inspect the pre-sync state: `channel.title`, `channel.subscriber_count`,
   `channel.banner_url` — all nil (Path A2 thin state).
7. Run the sync inline:
   ```ruby
   ChannelSync.new.perform(channel.id)
   channel.reload
   ```
8. Inspect the post-sync state:
   - `channel.title` matches the channel's title on YouTube.
   - `channel.handle` matches the channel's `@handle` (or nil if the channel has
     no handle).
   - `channel.subscriber_count`, `channel.view_count`, `channel.video_count` are
     populated as integers.
   - `channel.banner_url` and `channel.avatar_url` are populated as YouTube CDN
     URLs (or nil if YouTube returned none).
   - `channel.published_at` is the YouTube creation timestamp (NOT
     `channel.created_at`).
   - `channel.last_synced_at` is within the last few seconds.
9. Inspect the audit row:

   ```ruby
   YoutubeApiCall.order(:id).last
   ```

   - `endpoint == "channels.list"`, `outcome == "success"`,
     `http_status == 200`, `duration_ms` populated.

10. Test the no-connection path:
    ```ruby
    disconnected = Channel.where(youtube_connection_id: nil).first
    ChannelSync.new.perform(disconnected.id) # no error
    disconnected.reload.last_synced_at # unchanged
    ```
11. Test the missing-channel path:
    ```ruby
    ChannelSync.new.perform(99_999_999) # no error
    ```
12. Test the change-log append-only enforcement:
    ```ruby
    log = ChannelChangeLog.create!(
      channel: channel, field: "title", old_value: "Old",
      new_value: "New", changed_at: Time.current,
      changed_by_user: User.first
    )
    log.update!(field: "handle") # raises ActiveRecord::ReadOnlyRecord
    log.destroy                  # raises ActiveRecord::ReadOnlyRecord
    ```
13. Sanity-check the 14-day helpers:

    ```ruby
    channel.update!(title_changed_at: 13.days.ago)
    channel.title_locked? # => true
    channel.title_unlock_at # => ~1 day from now

    channel.update!(title_changed_at: 15.days.ago)
    channel.title_locked? # => false
    channel.title_unlock_at # => nil
    ```

14. `bundle exec rspec` — green.
15. `bundle exec rubocop` — green.

## Cross-stack scope

- **Rails (Web Puma)** — **in scope.** Schema + model + service + job.
- **MCP** — **out of scope.** No tool changes. A future `get_channel` MCP tool
  could expose the new columns; captured as a parent-spec follow-up.
- **`pito` CLI** — **out of scope.** The CLI's channel surface is read-only and
  presents the existing thin Channel today; surfacing the new fields is a later
  concern.
- **Cloudflare Pages website** — **out of scope.**

## Open questions

None. Every decision is locked by the parent spec (`11`) or by this sub-spec's
"Files touched" / "Specs" sections. The implementation agent proceeds directly
from this document without returning to the master agent for clarification.

Standing reminders (carried from the parent spec, not open questions for 11a):

- **D2 / Q9 — avatar editability verification** runs as a separate research
  dispatch BEFORE 11c (edit form) is dispatched. 11a's `avatar_url` column is
  display-only-cache regardless of the outcome (D12).
- **Q1 — title / handle live-API editability verification** runs as a separate
  research dispatch BEFORE 11c. 11a's `title` / `handle` columns exist
  regardless; they cache whatever the API returns.
- **Q4 — watermark timing live-API option set verification** runs before 11c
  surfaces the timing selector. 11a's `watermark_timing` validator uses all four
  documented values; if the API drops one, the validator shrinks in 11c.
