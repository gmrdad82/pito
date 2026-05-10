# Security audit — Phase 12: Video schema expansion + edit surface + pre-publish checklist

**Branch:** `main` **Spec:**
`docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-12-video-schema-expansion.md`
**Audit run:** 2026-05-10

## Verdict

**MERGE WITH FIX-FORWARD.** No Critical / High findings. 2 Medium worth
scheduling (F1 token refresh, F2 HTTP timeouts). 2 Low, 5 Informational.

## Per-concern verification (all genuinely guarded)

1. **Smuggle guards** — no bypass paths. Indifferent-access checks both symbol +
   string keys. VideoPolicy.permit dropping reinforced. `pre_publish_*` booleans
   absent from EDITABLE_ATTRS, silently filtered.
2. **`update_video` MCP two-step preview** — side-effect-free. Hardcoded
   EDITABLE_ATTRS-derived whitelist, no method-injection.
3. **`publish_video` MCP** — `pre_publish_complete?` gate fires before any
   write, on both preview and confirm paths.
4. **`VideoSyncBack` outbound HTTP** — partial coverage. See F1 + F2 below.
5. **Pre-publish booleans** — server-side validators reject if
   `YesNo.from_yes_no(perms[k])` doesn't evaluate true. Hidden-input + checkbox
   yes/no pattern correct. MCP enforces persisted booleans + timestamp.
6. **`Project has_many :videos, dependent: :nullify`** — both Rails callback +
   DB FK aligned.

## Findings

### F1. Skip token refresh — false `needs_reauth: true` on benign expiry (MEDIUM)

- **Location:** `app/services/youtube/videos_client.rb:93-151`,
  `app/services/youtube/videos_reader.rb:46-98`,
  `app/jobs/video_sync_back.rb:21-59`
- **Description:** Phase 12 services don't inherit the legacy `Youtube::Client`
  pattern of `ensure_token_fresh!` + retry-on-AuthorizationError-after-refresh.
  Result: a connection whose access_token simply expired (default 1 hour) but
  whose refresh_token is healthy gets locked out of edits.
- **Recommendation:** Mirror legacy: call
  `Youtube::TokenRefresher.call(@connection) if @connection.access_token_expired?`
  before API calls. On first 401, attempt one refresh-retry before giving up.
  Only persist `needs_reauth: true` after refresh itself fails.

### F2. No HTTP timeouts on YouTube Data API client (MEDIUM)

- **Location:** `app/services/youtube/videos_client.rb:153-157`,
  `videos_reader.rb:100-104`
- **Description:** `YouTubeService.new` constructed with no `client_options` /
  `request_options`. Hung TCP connect ties up Sidekiq worker.
- **Recommendation:** Set `client_options.send_timeout`, `open_timeout`,
  `read_timeout`. 10s open / 30s read aligns with legacy pattern + Sidekiq's 25s
  shutdown.

### F3. `to_unsafe_h` parameter laundering smell (LOW)

- **Location:** `app/controllers/videos_controller.rb:73-82`
- **Description:** `to_unsafe_h` strips strong-params marking. Works today
  (VideoPolicy.permit explicit) but obscures boundary.
- **Recommendation:** Permit first, then translate `tags_csv`. Or move CSV
  translation to Stimulus pre-submit.

### F4. Project deletion + nullify doesn't enqueue VideoSyncBack (LOW informational)

- **Location:** `app/models/project.rb:22`, `app/models/video.rb:65-69, 165-167`
- **Description:** `project_id` in WRITABLE_FIELDS but build_payload doesn't
  serialize it. Cascade-nullify skips after_update_commit so no sync. Not a real
  issue (project_id is local-only) but flag for clarity.
- **Recommendation:** Drop `project_id` from WRITABLE_FIELDS or comment-document
  local-only.

## Out-of-scope but noted

- Unscoped `Video.find` — consistent with single-install posture; finding only
  when multi-user ships.
- 2 obsolete brakeman ignore entries.
- `VideoPublish` Sidekiq job is dead code (never enqueued).
- `build_oauth_credentials` defines a class per call (style).
- No rate limit on `update_video` MCP — quota exhaust risk; Phase 16 hardening
  territory.

## Quality gate evidence

- Brakeman strict: 5 pre-existing warnings, 0 new.
- Bundler-audit: clean.
- No new dependencies.

## Summary

- Critical: 0
- High: 0
- Medium: 2 (F1, F2)
- Low: 2 (F3, F4)
- Informational: 5
