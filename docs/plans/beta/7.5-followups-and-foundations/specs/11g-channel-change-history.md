# Phase 7.5 — Step 11g — Channel Change History View

> Sub-spec of Step 11 (Channel Detail Page). Adds the user-facing surface on
> top of the existing `channel_change_logs` audit table (created by Step 11a):
> a per-channel chronological history page, a `[changes]` link from the
> channel show heading, an MCP `channel_changes_list` tool, and the JSON
> branch that mirrors the Phase 21 list-endpoint contract.
>
> Source of truth: parent Step 11 spec, Locked decisions **D6**
> (`channel_change_logs` table — append-only audit of title / handle edits)
> and **D17** (keep-all retention — no expiration, volume trivial under the
> 14-day rate limit on title + handle).

---

## Goal

The `channel_change_logs` audit table is already in place (Step 11a) and
already gets rows written by Step 11i's `[apply changes]` path (per its
acceptance bullet: "`title` and `handle` pushes write a `ChannelChangeLog`
row"). What is missing is the user-facing way to look at that audit trail.

This sub-spec ships three readers — one HTML, one JSON, one MCP — over the
existing table. None of them write. The trail is append-only at the model
level (rows raise `ActiveRecord::ReadOnlyRecord` on update / destroy per
Step 11a's contract); these readers honor that by surfacing it but never
mutating it.

The headline UX: on `/channels/:slug`, the heading actions row gains a
`[changes]` bracketed link next to the existing actions. Clicking it lands
the user on `/channels/:slug/history`, a chronological list (newest first)
of every title / handle change with old → new, relative timestamps, and the
user who made the change. Empty state when there are no rows. JSON branch
under the same URL. MCP tool `channel_changes_list` mirrors the Phase 21
list-tool pagination shape so Claude Mobile can ask "what title changes has
this channel had recently?" and get a clean answer.

Per D17, no expiration. The view paginates so the page stays cheap even if
the trivial-volume assumption ever breaks.

## Files touched

### New

- `app/controllers/channels/change_logs_controller.rb` — new. Single
  `#index` action. HTML + JSON branches. Loads the channel by slug via the
  existing `Channel.friendly.find` finder, paginates the changes newest
  first, renders the page or the JSON envelope.
- `app/views/channels/change_logs/index.html.erb` — new. Renders the page
  body: H1, lead paragraph (one-sentence-per-line per project rule B),
  table inside a `pane--standalone`, pagination footer, empty state.
- `app/views/channels/change_logs/index.json.jbuilder` — new. The JSON
  envelope per the Phase 21 list-endpoint contract (`changes` array +
  pagination meta).
- `app/decorators/channel_change_log_decorator.rb` — new IF the JSON
  shape needs derived fields (the spec uses `old_value` / `new_value`
  directly; the only derived field is `changed_by_email` lookup via the
  `User` association). If the controller can hydrate the same shape in
  the jbuilder template without a decorator, skip the decorator. The
  rails-impl agent decides; see Open question 5.
- `app/mcp/tools/channel_changes_list.rb` — new. Read-only tool on the
  `app` scope. Input: `channel` (slug or id), `page` (optional, default
  1). Returns the same envelope shape as the JSON branch (per the Phase
  21 / Phase 23 list-tool pattern). Cookie-auth not relevant; bearer +
  scope check via `Mcp::ToolAuth.require_scope!`.

### Edited

- `config/routes.rb` — edit. Add the nested resource:

  ```ruby
  resources :channels, only: [...existing...] do
    # ...existing nested routes...
    resources :change_logs, only: :index, path: "history",
              controller: "channels/change_logs", as: :change_logs
  end
  ```

  Resulting URLs:
  - `GET /channels/:channel_id/history` → `channels/change_logs#index`
    (HTML).
  - `GET /channels/:channel_id/history.json` → same action, JSON branch.

  Named route helper: `channel_change_logs_path(channel)` →
  `/channels/<slug>/history`. The `path:` override removes the
  `change_logs` URL segment in favor of the canonical `history` term the
  user expects to see.

- `app/views/channels/show.html.erb` — edit. Add the `[changes]`
  `BracketedLinkComponent` in the heading actions row, alongside whatever
  `[sync]` / `[edit]` / `[disconnect]` actions Step 11b's show page
  already renders. Strict tightening per project rule A — `[changes]`,
  no inner spaces.

### Specs

- `spec/requests/channels/change_logs_spec.rb` — new. Happy + sad + edge
  + flaw branches per the Spec Pyramid sweep.
- `spec/views/channels/change_logs/index_html_spec.rb` — new. View spec
  rendering the table, empty state, and pagination links.
- `spec/views/channels/change_logs/index_json_spec.rb` — new. jbuilder
  shape spec — asserts the wire envelope per the Phase 21 contract.
- `spec/mcp/tools/channel_changes_list_spec.rb` — new. MCP tool spec
  mirroring the Phase 21 / Phase 23 list-tool patterns.
- `spec/decorators/channel_change_log_decorator_spec.rb` — new ONLY if
  the decorator is extracted (see "Files touched / New" above).
- `spec/system/channel_change_history_spec.rb` — new. ONE thin scenario
  for the critical user journey (per spec pyramid rule D10 — system
  specs are selective).

Model + table specs are already covered by Step 11a's `channel_change_logs`
work and are NOT in scope for this sub-spec. This sub-spec MUST NOT add
write-side specs (the table is append-only and Step 11a + Step 11i own
the write paths).

## Acceptance

- [ ] `GET /channels/:slug/history` renders 200 when the channel exists.
- [ ] `GET /channels/:slug/history` renders 404 when the channel slug
      does not resolve via `Channel.friendly.find` (mirrors the existing
      channel show 404 path).
- [ ] The page H1 reads `Change history — <channel display label>`. The
      display label follows whatever Step 11b's show page uses for the
      heading (so the two pages agree). See Open question on labeling.
- [ ] Lead paragraph under H1 uses one-sentence-per-line `<br>` style
      (project rule B), e.g.:
      ```
      Title and handle edits are appended here automatically.
      <br>
      Pito does not edit or delete past entries.
      ```
- [ ] Page body is wrapped in `pane--standalone` (project rule C). No
      `framed-block` (orphaned per the canonical reference).
- [ ] Table columns, in order: `field` · `old → new` · `changed at` ·
      `changed by`. Newest first. Field values are `title` or `handle`
      (the only two values Step 11a's enum / validation allows).
- [ ] `old → new` column renders old / new values as plain text. ERB
      auto-escapes both — a value like `<script>alert(1)</script>`
      appears as literal angle-bracket text, never as a script node.
      System spec asserts this.
- [ ] `changed at` column renders relative time (e.g. `2 hours ago` via
      the existing `time_ago_in_words` / `distance_of_time_in_words`
      helper) with the absolute UTC timestamp as the `<time>` element's
      `title` attribute (existing project pattern for hover-to-see-
      absolute).
- [ ] `changed by` column renders the email of the user in
      `changed_by_user_id`. If the FK is null (legacy rows or system-
      generated rows — possible if Step 11i ever auto-creates one), the
      cell renders the muted text `system` per project rule on muted
      copy (`#555`). Confirm exact label via Open question 2.
- [ ] Empty state: when the channel has zero change-log rows, render the
      muted line `No changes yet` (project muted token `#555`); no
      table is rendered.
- [ ] Pagination: page size 50 (matches Phase 21 / `NotificationsController`
      precedent). Newest first. Footer renders `[previous]` / `[next]`
      bracketed links per project rule A. `page=` query param. Out-of-
      range pages render empty body, not 404 (mirrors the
      `NotificationsController` pattern: `@page = [params[:page].to_i,
      1].max`).
- [ ] `[changes]` link is rendered on `/channels/:slug` in the heading
      actions row using `BracketedLinkComponent` with label `changes`
      (project rule A — no inner spaces). The link's `href` resolves to
      `channel_change_logs_path(@channel)`.
- [ ] `GET /channels/:slug/history.json` returns the Phase 21 list-
      endpoint envelope:
      ```json
      {
        "changes": [
          {
            "id": 42,
            "field": "title",
            "old_value": "Old title",
            "new_value": "New title",
            "changed_at": "2026-05-11T14:23:00Z",
            "changed_by": { "id": 1, "email": "owner@example.com" }
          }
        ],
        "pagination": {
          "page": 1,
          "per_page": 50,
          "total": 1,
          "total_pages": 1
        }
      }
      ```
      `changed_at` is ISO-8601 UTC. `changed_by` is null when the FK is
      null. The envelope keys exactly match the Phase 21 contract — no
      camelCase, no abbreviations.
- [ ] MCP tool `channel_changes_list` registered on the `app` scope (per
      ADR 0004 — only `dev` + `app` exist). Input schema: `channel`
      (string, required — slug or numeric id), `page` (integer,
      optional, default 1). Returns the same envelope as the JSON
      branch above. Errors mirror the Phase 21 / Phase 23 list-tool
      conventions:
  - Channel not found → tool returns the standard not-found error
        envelope (see existing list-tool reference).
  - Missing required `channel` input → standard validation-error
        envelope.
- [ ] MCP tool wired into `app/lib/scopes.rb` and the MCP catalog so
      `bin/mcp` and `bin/mcp-web` both expose it. Tool spec asserts the
      registration.
- [ ] No write surface introduced anywhere. The controller, the view,
      the jbuilder, the decorator, and the MCP tool all read-only.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`
      introduced (project hard rule).
- [ ] All bracketed labels follow project rule A — `[changes]`,
      `[previous]`, `[next]`. No inner spaces.
- [ ] External booleans (if any are introduced in the JSON / MCP
      response) use `"yes"` / `"no"` per project rule E. None are
      currently planned in this envelope; flag if implementation needs
      to introduce one.
- [ ] Full spec sweep complete: request · view (html + json) · MCP
      tool · system (selective) · decorator (only if extracted) — per
      spec pyramid rule D.

## Schema

No migration. The `channel_change_logs` table already exists from Step
11a with the following columns (recap, not introduced here):

| column                | type      | notes                                          |
| --------------------- | --------- | ---------------------------------------------- |
| `id`                  | bigserial | PK.                                            |
| `channel_id`          | bigint    | FK → `channels.id`, NOT NULL, indexed.         |
| `field`               | string    | NOT NULL. Value in `{"title", "handle"}`.      |
| `old_value`           | text      | nullable (handles may be nil pre-set).         |
| `new_value`           | text      | NOT NULL.                                      |
| `changed_at`          | timestamp | NOT NULL. When the change happened.            |
| `changed_by_user_id`  | bigint    | FK → `users.id`, nullable.                     |
| `created_at`          | timestamp | NOT NULL.                                      |
| `updated_at`          | timestamp | NOT NULL (will equal `created_at`).            |

The table is append-only at the model level: `ChannelChangeLog#readonly?`
returns `true` post-create, raising `ActiveRecord::ReadOnlyRecord` on
update / destroy. This sub-spec only reads; no interaction with that
guard.

## Controller contract

`Channels::ChangeLogsController#index`:

1. Load `@channel = Channel.friendly.find(params[:channel_id])` — 404
   on miss (the friendly finder raises `ActiveRecord::RecordNotFound`).
2. Compute `@page = [params[:page].to_i, 1].max` (matches the
   `NotificationsController` pagination shape).
3. Build scope: `@channel.channel_change_logs.order(changed_at: :desc)`.
   `Channel#channel_change_logs` is the `has_many` association declared
   by Step 11a — confirm presence before dispatch (Open question 4).
4. `@total = scope.count`,
   `@total_pages = [((@total + PER_PAGE - 1) / PER_PAGE), 1].max`,
   `@logs = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)`.
5. `respond_to do |format|`:
   - `format.html { render :index }`
   - `format.json { render :index }` — jbuilder template owns shape.

The `PER_PAGE = 50` constant lives on the controller, matching the
`NotificationsController` precedent.

## MCP tool contract

`Mcp::Tools::ChannelChangesList`:

- Scope: `app` (per ADR 0004; the destructive `yt:destructive` scope
  collapses into `app`; this tool is read-only, so `app` is the only
  candidate).
- Input schema (JSON Schema, ratchet to the Phase 21 / Phase 23 list-
  tool shape):

  ```json
  {
    "type": "object",
    "properties": {
      "channel": {
        "type": "string",
        "description": "Channel slug (UC-id portion of channel_url) or numeric id."
      },
      "page": {
        "type": "integer",
        "minimum": 1,
        "default": 1
      }
    },
    "required": ["channel"]
  }
  ```

- Resolution: `Channel.friendly.find(input["channel"])`. Miss → standard
  list-tool not-found envelope (mirror Phase 21).
- Return: the same envelope as the JSON branch above. Encoded as a JSON
  string in the MCP `text` content block, per the existing list-tool
  pattern in `app/mcp/tools/`.
- Failure modes:
  - Channel not found → mirror Phase 21 / Phase 23 list-tool not-found
    envelope.
  - Missing required `channel` input → standard MCP input-validation
    envelope (the `mcp` gem owns this; the tool's spec asserts it).

The architect-spec decision to expose this as a list tool (and NOT a
single-channel `channel_show` field) follows the existing pattern: the
audit trail is a paginated collection per channel; the natural MCP
verb is `list`, not `show`.

## Manual test recipe

Preconditions:

- `bin/dev` up. Logged in as the seed owner.
- At least one Channel exists. (`bin/rails runner 'p Channel.first.id'`).
- At least one `ChannelChangeLog` row exists for that channel. Either
  let Step 11i's `[apply changes]` path create one organically, or
  seed manually for the test:

  ```bash
  bin/rails runner "
    ChannelChangeLog.create!(
      channel:           Channel.first,
      field:             'title',
      old_value:         'Old test title',
      new_value:         'New test title',
      changed_at:        2.hours.ago,
      changed_by_user_id: User.first.id
    )
  "
  ```

Steps:

1. Open `/channels/<slug>`. Confirm a `[changes]` bracketed link appears
   in the heading actions row (next to `[sync]` / `[edit]` /
   `[disconnect]` per Step 11b's layout).
2. Click `[changes]`. URL becomes `/channels/<slug>/history`.
3. Confirm the page H1 is `Change history — <channel label>` and the
   lead paragraph reads "Title and handle edits are appended here
   automatically. / Pito does not edit or delete past entries." (one
   sentence per line).
4. Confirm the table has one row with columns: `title`, `Old test
   title → New test title`, `2 hours ago` (relative), and the seed
   owner email.
5. Hover the `2 hours ago` cell. Confirm the absolute UTC timestamp
   appears in the tooltip / `title` attribute (date + time, e.g.
   `2026-05-11 12:23:00 UTC`).
6. Empty-state smoke: delete the row
   (`bin/rails runner 'ChannelChangeLog.delete_all'` — note this uses
   `delete_all` which bypasses the `readonly?` guard, NOT `destroy_all`;
   in app code we never delete, this is for teardown only). Refresh
   `/channels/<slug>/history`. Confirm the muted `No changes yet` line
   replaces the table.
7. Pagination smoke: seed 55 rows (50 + 5) with the runner
   `bin/rails runner '55.times { |i| ChannelChangeLog.create!(channel:
   Channel.first, field: "title", old_value: "t#{i}", new_value:
   "t#{i + 1}", changed_at: i.days.ago, changed_by_user_id:
   User.first.id) }'`. Reload the page. Confirm 50 rows on page 1,
   `[next]` link to `?page=2`, 5 rows on page 2, `[previous]` link
   back to page 1.
8. JSON smoke:

   ```bash
   curl -sS -H "Accept: application/json" --cookie-jar /tmp/c \
     "http://127.0.0.1:3027/login" >/dev/null
   # ... login ...
   curl -sS -H "Accept: application/json" --cookie /tmp/c \
     "http://127.0.0.1:3027/channels/<slug>/history.json" | jq .
   ```

   Confirm the response matches the envelope in "Acceptance" above
   (`changes` array, `pagination` object).
9. MCP smoke (with a bearer token from `/settings/tokens`):

   ```bash
   curl -sS -X POST http://127.0.0.1:3028/mcp \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0", "id": 1, "method": "tools/call",
       "params": { "name": "channel_changes_list",
                   "arguments": { "channel": "<slug>", "page": 1 } }
     }' | jq .
   ```

   Confirm the response wraps the same envelope as the JSON branch.

Teardown:

```bash
bin/rails runner 'ChannelChangeLog.delete_all'
```

(again, `delete_all` is the teardown bypass; production code never
deletes — D17 retention is keep-all.)

## Cross-stack scope

- **Rails web app** — in scope. Controller + views + decorator (maybe) +
  show-page link + routes + specs.
- **Rails JSON API** — in scope. JSON branch on the same controller per
  the Phase 21 contract.
- **MCP** — in scope. One read-only tool `channel_changes_list` on the
  `app` scope. Catalog entry in `app/lib/scopes.rb` if the spec sweep
  reveals a per-tool registration there; otherwise wired through the
  existing tool registry pattern under `app/mcp/tools/`. Tool spec
  asserts registration.
- **`pito` CLI** — SKIPPED for this sub-spec. The CLI's channel-detail
  screen does not yet expose a change history surface. CLI parity
  picks this up under the per-domain CLI parity work unit (work unit
  10 in `docs/realignment-2026-05-09.md`). Cross-reference the
  follow-up entry "CLI feature-parity sweep" in
  `docs/orchestration/follow-ups.md`.
- **Website (`extras/website/`)** — out of scope. Marketing surface.

## Open questions

1. **Pagination page size.** 50 per page (matches `NotificationsController`
   precedent + Phase 21 envelope) or 25 (more readable on mobile)?
   **Recommendation:** 50, matching the existing precedent. Volume per
   channel per year is trivial (under 26 rows max given the 14-day rate
   limit on title + handle per D6), so per-page size is mostly aesthetic
   — but project precedent is 50 and it costs nothing to follow it.
   Confirm or flip.

2. **`changed_by_user_id` rendering.** Show the user's `email` (clear,
   single-user-today) or a less identity-leaking shape like `user N` or
   `owner` (single-user-today, so all rows resolve to the same owner)?
   **Recommendation:** email. Pito is single-install + multi-user per
   ADR 0003; all authenticated users have install-wide access so an
   email surface on an audit row is not a leak. When the FK is null
   (legacy rows, possible system rows), render the muted `system`
   text. Confirm or flip.

3. **Relative time format.** Use the existing helper pattern (relative
   like `2 hours ago` + absolute UTC on hover via `title=`) or render
   absolute UTC inline? **Recommendation:** relative + absolute on
   hover — matches the existing project pattern (per the muted-helper
   convention used elsewhere on show pages). Confirm.

4. **`channel_change_logs` `has_many` association presence.** The
   controller relies on `Channel#channel_change_logs` (the standard
   `has_many` accessor). Step 11a's spec declares the model and the
   table; this sub-spec assumes the association is declared on
   `Channel` already. **If Step 11a did not add the `has_many`, this
   sub-spec needs to add it (one line) plus the matching model spec
   stub.** Architect-review: confirm with the user before dispatch
   (cheap to add either way; only worth flagging because it could
   slip out of scope between sub-specs).

5. **`ChannelChangeLogDecorator` extraction.** The JSON shape only
   needs `changed_by_email` lookup on top of the raw columns; the
   jbuilder template can do that with `log.changed_by_user&.email`
   inline. Do we extract a decorator anyway (consistency with other
   audit surfaces) or skip it (one fewer file)? **Recommendation:**
   skip the decorator unless the rails-impl agent finds a second
   derived field landing soon (e.g., a future "kind" or "scope" tag).
   The user's note on "Plan Draper for JSON/HTML unification" in
   their MEMORY.md is the longer arc; the decorator can land in that
   broader Draper pass without slowing this sub-spec. Confirm.

6. **`created_at` exposure.** The table has both `changed_at` (when the
   change actually happened) and `created_at` (when the row was
   inserted). These will typically be identical for the append-only
   audit pattern, but they could differ if Step 11i ever back-fills.
   Expose `created_at` in the row (extra column / extra JSON key) or
   only `changed_at`? **Recommendation:** only `changed_at`. The row's
   `created_at` is an implementation detail. If a future debugging
   case needs it, a small `_debug` rake task can dump it without
   surfacing it in the user-facing view. Confirm.

7. **Empty-state copy.** Exact wording: `No changes yet` (
   recommendation) vs. `No title or handle edits recorded` (more
   specific). **Recommendation:** `No changes yet` — short, matches
   the muted-line idiom on other Pito list pages. Confirm.

8. **Heading actions row order.** Where does `[changes]` sit relative
   to `[sync]` / `[edit]` / `[disconnect]`? Project convention on
   action ordering: navigation / detail-views first, mutations
   second, destructive last. **Recommendation:** `[changes]` is a
   navigation / detail view (read-only history), so it sits BEFORE
   `[sync]` and `[edit]`. Exact slot: leftmost of the actions row.
   Confirm; architect-review of Step 11b's show.html.erb at dispatch
   time will confirm the exact existing order without ambiguity.

9. **JSON envelope key for the relation.** The Phase 21 list-endpoint
   envelopes use the plural noun of the resource (`notifications`,
   `entries`, etc.). The natural plural here is `changes` (the
   user-facing noun) or `change_logs` (the model name). **
   Recommendation:** `changes` — that is what the user is looking
   at; `change_logs` is an implementation detail of the model name.
   This also keeps symmetry with the URL segment (`/history`) and
   the MCP tool name (`channel_changes_list`). Confirm or flip.

10. **MCP tool name.** `channel_changes_list` (recommendation) vs.
    `channel_history_list` vs. `list_channel_changes`. Project
    convention per existing tools (`list_docs`, `read_doc`,
    `save_note`, `delete_records`, `sync_records`) is mixed —
    `<noun>_<verb>` and `<verb>_<noun>` both exist. **
    Recommendation:** `channel_changes_list` — `<noun>_<verb>` form,
    matches the Phase 21 `notifications_list` and Phase 23
    `videos_diffs_list` precedents (assuming they exist; confirm at
    dispatch time by cross-checking the catalog). If those
    precedents use `list_<noun>`, flip to `list_channel_changes` for
    consistency.

## Cross-references

- Parent spec: Step 11 (Channel Detail Page) — locked decisions D6
  (`channel_change_logs` table) and D17 (keep-all retention).
- Sibling sub-specs:
  - `specs/11h-calendar-reminder-integration.md` — same pattern of
    sitting on top of an existing parent-spec table without writing
    to it.
  - `specs/11i-daily-diff-check-and-resolution.md` — Q-CHANGELOG-
    FIELDS notes that this audit table is intentionally narrow to
    `title` / `handle`; this sub-spec inherits that narrowness.
- Phase 21 — JSON parity contract for list endpoints (envelope shape
  + pagination meta).
- Phase 23 — MCP list-tool patterns (referenced for the tool's
  envelope encoding).
- `docs/orchestration/follow-ups.md` — "CLI feature-parity sweep"
  entry under `## Open`; the CLI surface for this history page lands
  in the per-domain CLI parity work unit, not here.
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` —
  justifies the `app` scope on the new MCP tool.
- `CLAUDE.md` — hard rule on yes/no boundary (E), single-install +
  multi-user (F), bracketed-link convention (A), one-sentence-per-
  line lead copy (B), `pane--standalone` (C), no JS confirms.
