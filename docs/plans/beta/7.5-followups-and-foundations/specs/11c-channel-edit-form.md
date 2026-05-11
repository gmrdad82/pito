# Step 11c — Channel Edit Form

> Sub-spec of `11-channel-management-and-preview.md` (parent). Covers ONLY the
> channel edit page at `/channels/:slug/edit`, its controller dispatch path
> through `Youtube::Client#update_channel`, the 14-day rate-limit gate UX
> (including the `[remind me]` integration handoff to 11h), and the three
> Stimulus controllers that drive the form's client-side affordances.
>
> **Depends on:** 11a (schema additions on `Channel`, `Youtube::Client`
> read-side `fetch_channel`, friendly-id slug on `Channel`).
>
> **Hands off to:** 11f (banner upload — this spec wires the partial slot; 11f
> owns the upload controller, the multi-size preview, and
> `Youtube::Client#upload_banner`), 11g (writes a `channel_change_logs` row from
> this spec's update path), 11h (the `[remind me on YYYY-MM-DD]` link POSTs to a
> calendar endpoint that 11h owns).
>
> **Not in this spec:** the show page (11b), the multi-layout preview modal
> (11d), the watermark preview frame (11e), the change-history view (11g — this
> spec only writes the log row), the calendar reminder model + endpoint (11h —
> this spec only renders the link element + a stub Stimulus controller whose
> POST target 11h fills in), the daily diff-check or `/diff` page (11i), avatar
> editing (D2 — out of scope pending Q9 verification).

## Goal

Ship the writable surface for a channel's editable YouTube fields. The user
opens `/channels/:slug/edit`, sees a form pre-populated from cached `Channel`
columns, edits any subset of fields, submits, and Pito pushes only the dirty
subset to YouTube via a single `Youtube::Client#update_channel` call (plus
`set_watermark` / `unset_watermark` when the watermark fields are touched, plus
the banner-upload handoff to 11f when a new banner file is present). On success,
the response caches into the local columns and the user lands back on
`/channels/:slug` with a flash notice. On any failure mode (14-day gate hit,
quota exhausted, OAuth re-auth required, validation reject, transient 5xx) the
form re-renders with a specific, user-readable error and the user's in-flight
edits stay intact.

The 14-day rate-limit gate on `title` and `handle` is enforced client-side per
D5 — when `title_changed_at` (resp. `handle_changed_at`) is within the window,
the input is replaced by a static message AND a `[remind me on YYYY-MM-DD]`
calendar link per D19. Defense-in-depth: a determined user bypassing the UI gets
YouTube's own 429 surfaced as a flash.

## Files touched

- `app/views/channels/edit.html.erb` — full form rewrite. Lead paragraph uses
  the one-sentence-per-line muted style (architect rule B). Form wrapped in a
  `.pane.pane--standalone` container (architect rule C).
- `app/controllers/channels_controller.rb` — extend `#update` to dispatch
  through `Youtube::Client#update_channel` (and `set_watermark` /
  `unset_watermark` when watermark fields are dirty); replace today's local-only
  `@channel.update(attrs)` path for the OAuth-connected case. Local-only update
  (no YouTube push) stays valid for channels with `youtube_connection_id` NULL —
  those channels show a banner explaining edits are local-only until a Google
  identity is linked.
- `app/services/youtube/client.rb` — add `#update_channel(channel, field_set)`
  (read-modify-write the entire targeted `part` per the destructive-PUT pattern;
  see Service design below), `#set_watermark(channel, io, timing, offset_ms)`,
  `#unset_watermark(channel)`. These flow through the existing `perform(...)`
  audit + quota chokepoint (Phase 7).
- `app/helpers/channels_helper.rb` — add `title_gate_open?(channel)`,
  `handle_gate_open?(channel)`, `title_unlock_date(channel)`,
  `handle_unlock_date(channel)`. Pure functions over `title_changed_at` /
  `handle_changed_at` + `14.days`.
- `app/javascript/controllers/links_repeater_controller.js` — Stimulus
  controller for the `links` jsonb editor (add row / remove row / enforce max 5
  client-side per D13).
- `app/javascript/controllers/file_upload_controller.js` — Stimulus controller
  for the watermark file picker (drag-drop + native picker per Q2 / D22).
  Hard-reject with specific reason per D14 (file type / file size / pixel
  dimensions). NOTE: the banner version of this controller lives in 11f; this
  spec ships only the watermark variant; if 11f lands first, the controller may
  already exist and this spec extends it. The agent picks the lower-friction
  path at implementation time.
- `app/javascript/controllers/reminder_link_controller.js` — Stimulus controller
  for the `[remind me on YYYY-MM-DD]` link. Stubbed here: intercepts the click,
  prevents default. The actual POST + JSON + toast wiring is owned by 11h. This
  spec ships an empty controller with the data attributes wired up so 11h slots
  in without touching ERB. If 11h lands first, this spec consumes the existing
  controller.
- Cross-cutting:
  - `config/routes.rb` — already defines
    `resources :channels, only: [:edit, :update, ...]`; no route changes needed.
  - `app/views/channels/_form_errors.html.erb` (new partial) — renders
    `flash.now[:alert]` plus per-attribute errors collected from the
    Youtube::Client error path.
- Specs:
  - `spec/requests/channels_controller_spec.rb` — extend with the full
    `PATCH /channels/:slug` matrix (see Acceptance).
  - `spec/services/youtube/client_spec.rb` — add `#update_channel`,
    `#set_watermark`, `#unset_watermark` coverage (WebMock-stubbed happy + every
    sad path).
  - `spec/helpers/channels_helper_spec.rb` — gate helpers.
  - `spec/system/channel_edit_form_spec.rb` — ONE end-to-end happy path system
    spec (description edit → save → cached → flash success). Selective per
    architect rule D — system specs are not blanket coverage.
  - `spec/javascript/` — not in the existing Rails JS spec convention; Stimulus
    coverage piggybacks on the system spec for now (open question — see below).

## Acceptance

### Schema (no migrations in this sub-spec; all columns ship with 11a)

- [ ] Edit form renders fields backed by `Channel#title`, `#handle`,
      `#description`, `#country`, `#default_language`, `#keywords`, `#links`,
      `#watermark_timing`, `#watermark_offset_ms`. `banner_url` is render-only
      here (file slot is owned by 11f's partial).
- [ ] No reference anywhere in this spec to `watermark_position` (D21).
- [ ] No avatar form field (D2 / Q9 pending).

### Server logic — `ChannelsController#update`

- [ ] When `params[:channel]` is empty (no dirty fields), short-circuit:
      redirect to `channel_path(@channel)` with flash notice "no changes to
      save."
- [ ] When the channel has no `youtube_connection_id`, the update path is
      local-only (`@channel.update(...)`). No `Youtube::Client` is instantiated.
      Flash: "channel updated locally — connect a google identity to push
      changes to youtube."
- [ ] When the channel has a `youtube_connection_id`, compute the `field_set`
      (the dirty subset of attribute changes; reject any key matching `title` or
      `handle` when its respective 14-day gate is open — defense in depth; the
      form should not let those fields submit). Dispatch in this order inside a
      single `Channel.transaction`: 1. If watermark-removal is requested
      (`params[:channel]        [:watermark_remove] == "yes"`), call
      `Youtube::Client#unset_watermark(@channel)`. 2. If a new watermark file is
      present, call
      `Youtube::Client#set_watermark(@channel, io, timing,        offset_ms)`. 3.
      If `field_set.any?` (excluding watermark + banner keys), call
      `Youtube::Client#update_channel(@channel, field_set)`. 4. Banner upload
      (if present) is dispatched separately via 11f's partial — that partial
      submits to the same `#update` action but with `params[:channel][:banner]`
      populated; on success, 11f's path writes `@channel.banner_url` directly.
      11c's spec just ensures the banner param key is whitelisted in strong
      params. 5. Cache the API response into local columns
      (`@channel.update(...)` with the YouTube-canonical values; this is what
      makes "Pito's cache is authoritative until next sync" work). 6. On `title`
      or `handle` change, set
      `title_changed_at`/`handle_changed_at = Time.current` (11g writes the
      `channel_change_logs` row from the same callback).
- [ ] On `Youtube::NeedsReauthError`: flag the connection
      (`@channel.youtube_connection.update!(needs_reauth: true)` or whatever
      Phase 7 / 9 exposed — verify against shipped code at impl time), redirect
      to `/settings/youtube` with flash: "google connection needs
      re-authorization."
- [ ] On `Youtube::QuotaExhaustedError`: re-render `:edit` with
      `flash.now[:alert] = "youtube api quota exhausted; try again     later."`
      Form values stay populated (user's edits are not lost).
- [ ] On a 14-day gate hit raised by YouTube (the 429 server-side path, not the
      client gate): re-render `:edit` with
      `flash.now[:alert] = "youtube limits title changes to 1 per 14     days; next available <YYYY-MM-DD>."`
      Same shape for handle.
- [ ] On any other transient 5xx (after the Phase 7 retry policy is exhausted):
      re-render `:edit` with
      `flash.now[:alert] = "youtube     is having trouble right now; please try again in a few minutes."`
- [ ] On client-side validation failure caught server-side (link with blank
      `url`, links count > 5, watermark `offset_ms` < 0, country not ISO-3166-1
      alpha-2 shape, default_language not BCP-47 shape): re-render `:edit` with
      per-attribute errors via the standard `errors.full_messages` path. Form
      values stay populated.

### Service — `Youtube::Client#update_channel(channel, field_set)`

- [ ] Maps Pito-shape snake_case keys in `field_set` to the canonical YouTube
      `channels.update` request body. The key → part mapping: - `title`,
      `description`, `country`, `default_language`, `keywords` →
      `brandingSettings.channel.<key>` (verify exact nesting against the live
      API at impl time — Phase 7 research dispatch may have already cached
      this). - `handle` → uses the dedicated handle-update endpoint if YouTube
      exposes one; otherwise `brandingSettings.channel.title` is the wrong
      target — verify per Q1 research before this sub-spec is dispatched (open
      question retained). - `links` →
      `brandingSettings.channel.unsubscribedTrailer` + `featuredChannelsUrls`
      per parent D13 — verify the actual shape against the live API.
- [ ] Follows the destructive-PUT pattern: BEFORE issuing `channels.update`,
      call `channels.list` with the parts being mutated, merge `field_set` into
      the response body, then PUT the merged body back. This prevents
      accidentally blanking sibling fields that YouTube treats as
      authoritative-on-PUT.
- [ ] Flows through the existing `perform("channels.update", "PUT")` chokepoint
      for audit + quota (Phase 7 contract).
- [ ] Returns the parsed response in pito-shape (snake_case Ruby Hash; never a
      `Google::Apis::YoutubeV3::Channel` struct — per the existing client
      convention).
- [ ] Raises `Youtube::NeedsReauthError` on 401 after refresh attempt.
- [ ] Raises `Youtube::QuotaExhaustedError` on the pre-call quota check
      exceeding budget.
- [ ] Raises `Youtube::RateLimitedError` (existing or new — name locked at impl
      time) on YouTube's 429 with `reason: "rateLimit"` AND the response
      indicates a title/handle 14-day rate hit. The controller catches this
      specifically and surfaces the unlock date.

### Service — `Youtube::Client#set_watermark(channel, io, timing, offset_ms)`

- [ ] Uploads `io` via `watermarks.set` with the canonical YouTube request body.
      No `position` parameter (D21).
- [ ] `timing` is one of `always`, `entire_video`, `offset_from_start`,
      `offset_from_end` (D16 / Q4). `offset_ms` is required when
      `timing in [offset_from_start,     offset_from_end]` and ignored
      otherwise.
- [ ] Flows through `perform("watermarks.set", "POST")`.
- [ ] Returns the cached `watermark_url` (parsed from the response).
- [ ] Raises the same error taxonomy as `update_channel`.

### Service — `Youtube::Client#unset_watermark(channel)`

- [ ] Calls `watermarks.unset` via the existing `perform` chokepoint.
- [ ] Clears `channel.watermark_url`, `channel.watermark_timing`,
      `channel.watermark_offset_ms` on success.

### Wire contracts (form params)

The form submits a multipart `PATCH /channels/:slug` with body:

```
channel[title]:           string
channel[handle]:          string             # optional; omitted when gate open
channel[description]:     string (multiline)
channel[country]:         string (ISO-3166-1 alpha-2; uppercase 2 chars)
channel[default_language]: string (BCP-47, e.g., "en", "en-US")
channel[keywords]:        string (space-separated by convention)
channel[links_attributes][N][title]: string
channel[links_attributes][N][url]:   string  (https://...)
channel[links_attributes][N][_destroy]: "yes" | "no"  (yes/no boundary, rule E)
channel[watermark]:       file (multipart upload, optional)
channel[watermark_timing]: enum string
channel[watermark_offset_ms]: integer (0..)
channel[watermark_remove]: "yes" | "no"  (yes/no boundary — D unsets the watermark)
channel[banner]:          file (multipart upload, optional; handled by 11f)
```

- [ ] Strong params permit all of the above. `links_attributes` uses Rails
      accepts_nested_attributes_for OR a manual sanitizer — the impl agent
      picks; either way only `[title, url, _destroy]` keys survive.
- [ ] Yes/no boundary (rule E) enforced on `_destroy` and `watermark_remove`.
      Internal coercion to Boolean happens in the controller, never in the form.
      No `true`/`false`/`1`/`0` anywhere on the wire.

### UX — 14-day gate (D5 / D19)

- [ ] When `title_gate_open?(@channel)`, the title input is replaced by a `<p>`
      containing: "title was changed on <YYYY-MM-DD>; youtube limits changes to
      1 per 14 days." Adjacent to that message, render
      `<a data-controller="reminder-link"     data-reminder-link-unlock-date-value="<YYYY-MM-DD>"     data-reminder-link-field-value="title"     data-reminder-link-channel-id-value="<id>" href="#">[remind me     on <YYYY-MM-DD>]</a>`.
      Bracketed-link convention (rule A), no inner spaces.
- [ ] Same shape for handle (gate helper checks `handle_changed_at`).
- [ ] The `reminder_link_controller` stub in this spec wires
      `data-action="click->reminder-link#create"` and a target for the toast
      container. 11h implements `#create` (POST to `/calendar/entries.json` with
      prefilled body per D19, render toast).
- [ ] Toast target: a
      `<div data-reminder-link-target="toast"     class="toast" role="status" aria-live="polite"></div>`
      sits in the form's lead paragraph area.

### UX — links repeater (D13)

- [ ] Initial render: each `channel.links` entry is a row with `[title]`,
      `[url]`, `[remove]` (bracketed). One blank row at the bottom when count
      < 5.
- [ ] `links_repeater_controller`:
  - `add` action — appends a new row with empty `title` + `url` inputs. Hides
    the `[+ add link]` button when count reaches 5.
  - `remove` action — sets the row's `_destroy` hidden input to `"yes"` and
    hides the row (server filters destroyed rows on PATCH; the row keeps its
    `links_attributes[N]` index intact).
- [ ] Server-side cap of 5 still enforced via `Channel` validation (defined in
      11a); client UI removal of `[+ add link]` is UX polish, not the gate.
- [ ] No JS `confirm` on remove (hard rule). Soft-removal pattern (Rails
      standard) — row hidden, `_destroy=yes`, user can undo by re-adding before
      submit.

### UX — watermark upload (D14 / D22)

- [ ] Pre-upload spec info visible before the user picks a file: "expected:
      800×800 PNG or JPEG; max <SIZE> MB" (size verified against YouTube's docs
      at impl time).
- [ ] `file_upload_controller` (watermark variant): on `change` / `drop`, read
      the file via `URL.createObjectURL` + `HTMLImageElement` natural dimensions
      OR `createImageBitmap`. Validate: file type ∈ {PNG, JPEG}, file size ≤
      max, pixel dimensions == 800×800 (or whatever YouTube's actual spec is).
- [ ] On reject, render an inline error naming the specific violation: "file
      type: PNG or JPEG required", "file size: exceeds <N> MB", or "pixel
      dimensions: 800×800 required". Form not submittable while reject state is
      active.
- [ ] On accept, show a small thumbnail preview before submit. The full
      multi-size watermark preview lives in 11e — the edit form shows only the
      picked thumbnail, not the player-mockup preview.
- [ ] `watermark_timing` is a `<select>` with 4 options (D16 / Q4). The
      `offset_ms` input is hidden unless `timing` is `offset_from_start` or
      `offset_from_end` (Stimulus
      `data-action="change->file-upload#toggleOffset"`).
- [ ] `[remove watermark]` bracketed link (rule A) sets a hidden
      `channel[watermark_remove]=yes` input and submits. The controller picks up
      the yes/no string and dispatches to `Youtube::Client#unset_watermark`.

### UX — banner upload slot

- [ ] The edit form includes a
      `<%= render "channels/banner_upload",     channel: @channel %>` slot. That
      partial is owned by 11f. 11c ships an empty partial with a TODO comment so
      the file exists and the form renders before 11f lands. (Impl agent
      confirms whether 11f has shipped; if so, the slot is wired against the
      shipped partial.)

### Test coverage (per architect rule D — spec pyramid)

#### Request specs (`spec/requests/channels_controller_spec.rb`)

- [ ] `PATCH /channels/:slug` — happy path, single dirty field (`description`
      only) — verifies only `description` lands in the `field_set` passed to
      `Youtube::Client#update_channel`.
- [ ] Happy path, multi-field dirty subset (title + description + country) —
      verifies all three land in one `Youtube::Client#update_channel` call.
- [ ] Happy path, watermark-only edit (new file uploaded) — verifies
      `set_watermark` called once, `update_channel` NOT called.
- [ ] Happy path, watermark removal (`watermark_remove=yes`) — verifies
      `unset_watermark` called.
- [ ] Happy path, no dirty fields — verifies short-circuit redirect with "no
      changes to save."
- [ ] Happy path, channel without `youtube_connection_id` — local- only update,
      no `Youtube::Client` instantiated.
- [ ] Sad — `Youtube::NeedsReauthError` raised by `update_channel` → connection
      flagged, redirect to `/settings/youtube` with flash.
- [ ] Sad — `Youtube::QuotaExhaustedError` raised → re-render `:edit` with
      flash; form values populated; assert no database mutation occurred.
- [ ] Sad — 14-day gate hit server-side (`RateLimitedError` with title/handle
      reason) → re-render `:edit` with unlock-date flash.
- [ ] Sad — transient 5xx (mock the underlying gem error) → re-render `:edit`
      with friendly flash.
- [ ] Sad — links validation reject (6th link, blank title, malformed URL) →
      re-render `:edit` with per-attribute errors.
- [ ] Sad — country format reject (not 2-char uppercase) → re-render `:edit`.
- [ ] Sad — `default_language` format reject (not BCP-47) → re-render `:edit`.
- [ ] Sad — watermark `offset_ms` negative → re-render `:edit`.
- [ ] Edge — defense in depth: user POSTs `title` change while the 14-day client
      gate is open → controller filters the title out of `field_set` AND
      surfaces a flash explaining the gate.
- [ ] Edge — transaction rollback: `update_channel` succeeds but the subsequent
      `@channel.update(...)` cache write fails (mock to raise) → the
      YouTube-side state has changed but Pito's cache hasn't; flash explains
      "your change pushed to youtube but pito's cache lagged; click sync to
      reconcile." (This is unavoidable — YouTube has no rollback API. The flash
      makes the divergence visible so the daily diff-check (11i) doesn't have to
      find it.)

#### Service spec (`spec/services/youtube/client_spec.rb`)

- [ ] `#update_channel` — verifies read-modify-write pattern: the service issues
      `channels.list` first, merges, then `channels.update`. WebMock asserts
      both calls fire in order.
- [ ] `#update_channel` — verifies pito-shape Hash response (no Google struct
      leak).
- [ ] `#update_channel` — happy + each error (`NeedsReauthError`,
      `QuotaExhaustedError`, `RateLimitedError`, 5xx retry).
- [ ] `#update_channel` — quota chokepoint hit (pre-call check raises before any
      HTTP request).
- [ ] `#update_channel` — audit row written via the `Auditor` mixin (KIND
      `"oauth"`, endpoint `"channels.update"`).
- [ ] `#set_watermark` — happy + 4 timing values + offset*ms required iff
      `offset_from*\*` + error taxonomy.
- [ ] `#unset_watermark` — happy + clears local columns + error taxonomy.

#### Helper spec (`spec/helpers/channels_helper_spec.rb`)

- [ ] `title_gate_open?` — true when `title_changed_at` within 14 days of
      `Time.current`; false when nil; false when older than 14 days; boundary
      (exactly 14 days) explicitly tested.
- [ ] Same matrix for `handle_gate_open?`.
- [ ] `title_unlock_date` — returns `title_changed_at + 14.days` formatted as
      `YYYY-MM-DD`; nil-safe (returns nil when `title_changed_at` is nil).
- [ ] Same for `handle_unlock_date`.

#### System spec (`spec/system/channel_edit_form_spec.rb`) — ONE happy path only

- [ ] User opens `/channels/:slug/edit` with a channel that has
      `youtube_connection_id` set. Form pre-populates from cached columns. User
      edits the description, submits. WebMock stubs `channels.list` +
      `channels.update`. User lands on `/channels/:slug` with flash "channel
      updated." and the page renders the new description.

#### Stimulus controller specs

- [ ] `links_repeater_controller` — covered indirectly by the system spec (add a
      link, remove a link, verify the form submits the expected
      `links_attributes` shape).
- [ ] `file_upload_controller` (watermark variant) — covered indirectly by the
      system spec OR deferred to 11f's spec coverage if 11f generalizes the
      controller. Open question.
- [ ] `reminder_link_controller` — stub only; 11h's spec covers the POST + toast
      flow.

### Docs touched

- [ ] No top-level docs touched (this is a sub-spec; the parent
      `11-channel-management-and-preview.md` already documents the decisions).
- [ ] After implementation lands and the user validates the manual playbook, the
      architect appends a session entry to
      `docs/plans/beta/7.5-followups-and-foundations/log.md` summarizing what
      was implemented.

## Manual test recipe

Prereqs:

- A channel with `youtube_connection_id` set (Phase 7 OAuth pair completed).
- A second channel WITHOUT `youtube_connection_id` (to exercise the local-only
  update path).
- The user has a tiny test channel they own on YouTube (NOT their main channel —
  title/handle edits burn the 14-day rate limit).

Steps:

1. `bin/dev`. Open `/channels/:slug/edit` for the connected test channel.
2. Lead paragraph reads one sentence per line (architect rule B). Form container
   has the `pane--standalone` background (rule C).
3. Edit ONLY the description. Add 2–3 paragraphs. Submit. Land on
   `/channels/:slug` with flash "channel updated." Reload — the new description
   renders.
4. Open `/channels/:slug/edit` again. The title input is hidden (because step 3
   didn't change the title, but if a prior session did — adjust this step to a
   fresh channel). The text "title was changed on <YYYY-MM-DD>; youtube limits
   changes to 1 per 14 days." renders. To the right:
   `[remind me on <YYYY-MM-DD>]`. Hovering shows the underline / pointer cursor
   (design.md rule).
5. Click `[remind me on YYYY-MM-DD]`. The page stays on `/channels/:slug/edit`.
   A toast renders saying "reminder created for <YYYY-MM-DD>." (Toast wiring is
   11h; in 11c-only builds the click is a no-op stub.)
6. Edit the country to `XX` (not a real ISO code — actually `XX` is
   reserved-for-private-use, but make this `99` or `usa` to trigger the
   validator). Submit. Form re-renders with "country must be an iso 3166-1
   alpha-2 code (2 uppercase letters)." Other field values stay populated.
7. Edit links. Add a link with blank URL. Submit. Form re-renders with "links
   must have a url." Add 6 links total. Submit. Form re-renders with "links
   cannot exceed 5." Remove one. Submit the form with 5 valid links. Land on
   show page; the links render.
8. Upload a 1280×720 PNG watermark (off-spec). The Stimulus controller
   hard-rejects in-browser: "pixel dimensions: 800×800 required." Form does not
   submit. Upload a 800×800 .gif. Reject with "file type: PNG or JPEG required."
   Upload a valid 800×800 PNG. Set timing to `offset_from_start`, `offset_ms` to
   `5000`. Submit. Show page renders the new watermark cache (preview lives on
   11e).
9. Click `[remove watermark]`. Confirmation goes through the `_action_screen`
   framework (per hard rule — NO `confirm()`). On confirm, watermark cleared.
10. On a channel WITHOUT `youtube_connection_id`, open the edit form. A banner
    above the form reads "this channel is not connected to a google identity;
    edits save locally only." Edit description. Submit. Flash: "channel updated
    locally — connect a google identity to push changes to youtube."
11. Simulate a quota exhaustion (or run after a real quota hit): submit any
    change → form re-renders with "youtube api quota exhausted; try again
    later." Form values intact.
12. Simulate a needs-reauth (revoke the Google token in the Google account
    settings, then submit): form re-renders / redirects to `/settings/youtube`
    with "google connection needs re-authorization."
13. `bundle exec rspec spec/requests/channels_controller_spec.rb spec/services/youtube/client_spec.rb spec/helpers/channels_helper_spec.rb spec/system/channel_edit_form_spec.rb`
    — green.
14. `bundle exec rubocop` — green.

## Cross-stack scope

- **Rails (Web Puma)** — **in scope.** All files listed above.
- **MCP** — **out of scope** for this sub-spec. A future
  `update_channel_metadata` MCP tool is captured as a follow-up in the parent
  spec; not part of 11c. The yes/no boundary is already honored in this spec's
  form params so MCP can follow the same shape later.
- **`pito` CLI** — **out of scope.** The CLI has no channel-edit surface yet
  (Phase 4 footage import only).
- **Cloudflare Pages website** — **out of scope.** Marketing surface, not app.

## Open questions

These need master-agent / user input before this sub-spec is dispatched to
rails-impl. None of them block writing the spec — they block implementation.

1. **Watermark client-side dimension validation.** D22 says hard- reject on
   dimension mismatch. The watermark spec per YouTube is typically 800×800
   PNG/JPEG, but the live API may accept other sizes (e.g., 1280×720). Verify
   against the live API (or a Q1-style research dispatch) before locking the
   `file_upload_controller`'s pixel-dimension assertion. If the live API is
   permissive, drop the client-side hard-reject to a soft warning and let the
   server confirm via YouTube's response.

2. **`[remind me]` button copy when the gate fires.** Bare verb
   (`[remind me on YYYY-MM-DD]`) or include the field name
   (`[remind me on YYYY-MM-DD for title]`)? The parent spec D19 uses the bare
   verb; if the user has two reminders queued (one for title, one for handle) on
   the same channel within overlapping windows, the bare form is ambiguous in
   the calendar listing. The parent's `Calendar::Entry#title` (e.g., "channel
   title unlock — <channel name>") disambiguates downstream, so the bare verb on
   the link itself stays unambiguous in context. Recommend: bare verb. Confirm
   with user.

3. **Links jsonb max-5 enforcement — client-only, server-only, or both?** Parent
   D13 says "capped at 5". This sub-spec proposes: server-side validation
   (authoritative) + client-side UI hides the `[+ add link]` button at count 5
   (polish). The alternative is server-only — simpler but the user can stage a
   6th row and only see the reject on submit. Recommend: both. Confirm with
   user.

4. **Inline crop for banner upload.** Parent D22 says "no inline crop" (user
   pre-crops in Canva). This sub-spec honors that. Re-confirm: if a future user
   (not the primary user) hits the banner upload and lands on the 16:9
   hard-reject, do we add a tiny in-browser crop step? Not blocking — flag as a
   Theta-phase consideration.

5. **`Youtube::Client#update_channel` handle update path.** YouTube exposes a
   separate handle-management endpoint distinct from `channels.update` (per
   pre-2024 docs; verify with the Q1 research dispatch). If true,
   `#update_channel` needs to branch: handle changes go through the dedicated
   endpoint, all other fields through `channels.update`. Either way, the
   controller's call site is unchanged
   (`Youtube::Client#update_channel(channel, field_set)` — the branching is
   internal). Confirm the endpoint shape before impl.

6. **Stimulus controller test coverage.** Rails JS specs are not in the existing
   project convention; the architect rule D pyramid covers ViewComponent +
   helper + request + service + selective system. The
   `links_repeater_controller` and `file_upload_ controller` are covered
   indirectly by the system spec, but their unit behavior (max-5 cap, file-type
   reject reason text, drag-drop visual state) is not covered. Worth a follow-up
   to introduce a thin Stimulus testing layer? Not blocking 11c — flag as a
   follow-up.

7. **Transaction boundary across `update_channel` + cache write.** YouTube has
   no rollback API; if `channels.update` succeeds and the local
   `@channel.update(...)` cache write fails, the user's YouTube channel has
   changed but Pito's view of it lags until the next sync. The Acceptance
   section above bakes a flash in for this case. Confirm: is the flash + "click
   sync" path acceptable, or do we re-fetch via `channels.list` and retry the
   cache write before surfacing the flash? Recommend: flash + sync. Re-fetch +
   retry could mask a deeper bug. Confirm with user.
