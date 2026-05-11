# 11f — Channel Banner Upload

## Goal

Replace the banner stub from 11c with a working upload flow on the channel edit
form. The user picks a JPEG / PNG via drag-drop zone or file-picker button, the
browser validates type / dimensions / aspect / size against YouTube's banner
spec, a multi-size preview renders before submit, and on submit Rails performs
the two-step YouTube call (`channelBanners.insert` to upload bytes, then
`channels.update` to set `brandingSettings.image.bannerExternalUrl`). The
resulting banner URL caches into `channels.banner_url` for fast page rendering.

Sourced from parent Step 11 spec decisions D3 (banner mutable via API), D14
(hard reject of non-compliant uploads), D22 (clear reasons on every rejection),
Q2 (file-picker + drag-drop, no inline crop), and Q5 (hard reject confirmed).

## Files touched

Rails app:

- `app/services/youtube/client.rb` — extend with `#upload_banner(channel, io)`
  (two-step: `channelBanners.insert` returns `bannerExternalUrl`, then
  `channels.update` sets `brandingSettings.image.bannerExternalUrl`). Both calls
  audited via `youtube_api_calls`.
- `app/controllers/channels_controller.rb` — `#update` already routes a dirty
  subset to YouTube; add the `banner_image` param branch that invokes the
  two-step upload, updates `channels.banner_url`, and re-renders the banner
  section via Turbo Stream on success. On YouTube-side failure, render the
  surfaced error in the form error area without crashing.
- `app/javascript/controllers/banner_upload_controller.js` (new) — Stimulus
  controller for drag-drop + file-picker + client-side validation (type,
  dimensions via `Image` constructor, aspect, size) + multi-size preview
  generation via `URL.createObjectURL`. Blocks form submit until the async
  client check passes; revokes object URLs after preview.
- `app/views/channels/_banner_upload.html.erb` — new partial replacing the 11c
  stub. Contains: spec info line, drag-drop zone, file-picker button, hidden
  file input, error area, multi-size preview container (web / mobile / TV — same
  shape as 11d preview).
- `app/views/channels/_banner.html.erb` — Turbo Stream target wrapping the
  cached banner display, swapped after a successful update.
- `app/views/channels/edit.html.erb` — render `_banner_upload.html.erb` in the
  banner section instead of the 11c stub.
- `app/views/channels/update.turbo_stream.erb` — append the banner partial swap
  branch.

Specs:

- `spec/services/youtube/client_spec.rb` — extend with `#upload_banner` happy +
  sad cases (403 quota, 5xx transient, 401 refresh, 400 dimensions rejected by
  YouTube despite client-side check, network timeout).
- `spec/requests/channels_controller_spec.rb` — `#update` with `banner_image`
  param: happy path (banner updates, `banner_url` cached, Turbo Stream renders),
  sad path (YouTube rejects → form error surfaced, no crash, `banner_url`
  unchanged).
- `spec/system/channels/banner_upload_spec.rb` — Stimulus controller via system
  spec: drag-drop file → preview; file-picker file → preview; oversize file →
  reject with size reason; wrong-aspect file → reject with aspect reason;
  wrong-type file → reject with type reason; too-small dimensions → reject with
  dimension reason; valid file → submit enabled, submit succeeds.

Cross-cutting:

- `config/initializers/rack.rb` (or equivalent) — bump multipart body size limit
  from default to handle the 6MB banner + headroom (see Open question).

## Acceptance

- [ ] `Youtube::Client#upload_banner(channel, io)` exists, performs the
      `channelBanners.insert` multipart upload, captures the returned
      `bannerExternalUrl`, then calls `channels.update` with
      `brandingSettings.image.bannerExternalUrl` set, and returns the cached URL
      string.
- [ ] Both YouTube API calls are audited via `youtube_api_calls` rows (one row
      per call, two rows per upload).
- [ ] On success, `channel.banner_url` is updated with the YouTube-returned URL.
- [ ] On YouTube-side failure (403 quota, 5xx, 400 dimensions, 401), the
      `Youtube::Client` returns a structured error; the controller surfaces the
      message in the form error area and leaves `banner_url` unchanged.
- [ ] 401 triggers token refresh per the existing Phase 7 refresh wrapper; on
      second 401, the connection is marked `needs_reauth`.
- [ ] `_banner_upload.html.erb` partial replaces the 11c stub and shows the
      spec-info line: "Banner: 2048x1152 minimum, 16:9 aspect, JPEG/PNG, max
      6MB".
- [ ] Drag-drop zone accepts files dropped onto it.
- [ ] File-picker button opens the OS file dialog and accepts the selected file.
- [ ] Client-side validation rejects on the four conditions with the exact
      messages:
  - "File type: JPEG or PNG required."
  - "Dimensions: minimum 2048x1152 required (got <W>x<H>)."
  - "Aspect ratio: 16:9 required (got <ratio>)."
  - "File size: max 6MB (got <size>)."
- [ ] All rejection reasons render simultaneously when multiple conditions fail
      (no silent rejects, no first-fail-only).
- [ ] Multi-size preview renders before submit using the same component shape as
      11d (web / mobile / TV size variants).
- [ ] Submit is blocked while the async client check is running; a progress
      indicator shows during validation.
- [ ] Successful submit triggers a Turbo Stream swap of the banner section
      instead of a full page reload.
- [ ] `URL.createObjectURL` blob URLs are revoked after preview generation
      completes.
- [ ] No JS `alert` / `confirm` / `prompt` used anywhere in the controller (per
      `CLAUDE.md` hard rules).
- [ ] Spec sweep: service spec for `#upload_banner`, request spec for `#update`
      with `banner_image`, system spec for the Stimulus controller flows (per
      spec-pyramid rules D in `docs/agents/architect.md`).
- [ ] `bundle exec rspec` green; `bundle exec rubocop` green; no Stimulus
      controller lint warnings.

## Manual test recipe

Preconditions: Phase 7 OAuth connected for one channel; logged in as owner.

1. `bin/dev` and visit `/channels/:id/edit` for a YouTube-connected channel.
2. Confirm the banner section shows the spec-info line and an empty drag-drop
   zone plus a `[pick file]` button.
3. Drag a non-JPEG / non-PNG file (e.g. a `.webp`) onto the zone. Expect the
   error "File type: JPEG or PNG required." Submit button stays disabled.
4. Drop a JPEG that is 1280x720. Expect "Dimensions: minimum 2048x1152 required
   (got 1280x720)." Submit stays disabled.
5. Drop a JPEG that is 2048x1000 (wrong aspect). Expect "Aspect ratio: 16:9
   required (got 2.048:1)." Submit stays disabled.
6. Drop a JPEG that is 8MB at 2048x1152. Expect "File size: max 6MB (got 8MB)."
   Submit stays disabled.
7. Click `[pick file]` and choose a 2048x1152 JPEG under 6MB. Expect: progress
   indicator briefly while the client check runs, then multi-size preview
   renders (web / mobile / TV variants), submit button enables.
8. Submit. Expect: two `youtube_api_calls` rows (one `channelBanners.insert`,
   one `channels.update`), the banner section swaps via Turbo Stream showing the
   new cached banner, no full page reload.
9. Verify `channels.banner_url` is populated in the DB
   (`bin/rails runner 'p Channel.find(:id).banner_url'`).
10. Force a YouTube-side failure (temporarily stub `Youtube::Client` to raise
    `Google::Apis::ClientError.new("imageDimensionsInvalid")` from a console
    session, or inject via the WebMock harness in the spec). Submit a valid
    client-side file. Expect: error message renders in the form area, page does
    not crash, `banner_url` unchanged, staged file remains visible so the user
    can re-pick.

Teardown: revert `banner_url` by clearing it via console if you want to retry
from scratch; otherwise leave it set.

## Cross-stack scope

- Rails app: in scope (the entire upload + cache + Turbo-Stream-swap flow).
- MCP: skipped — banner upload is interactive only; no MCP tool surface in this
  phase. Re-evaluate if a future "publish branding from CLI" surface is
  requested.
- `pito` CLI: skipped — TUI does not handle file pickers in this phase.
- Website: skipped — unrelated.

## Open questions

1. Should the form submit be blocked until the async client-side dimension check
   passes, or should it attempt the server submit anyway? Recommendation: block
   submit until client check passes; surface a progress indicator while
   validating. Confirm.
2. Rails multipart upload size limit defaults to ~5MB in some stacks; the banner
   spec allows up to 6MB. Confirm we should raise the limit (nginx + Rails) to
   10MB to handle 6MB banner + headroom, and where the change lands
   (`config/initializers/rack.rb` vs. nginx config — the latter is out of repo
   scope).
3. `URL.createObjectURL` browser support is universal in evergreen browsers;
   confirm that revoking blob URLs after preview generation is acceptable, and
   that we do not need to keep the blob alive for re-preview after a failed
   server submit (Open question 5 covers the re-pick case).
4. After successful upload, should the page reload to show the cached banner, or
   use a Turbo Stream swap of the banner section? Recommendation: Turbo Stream
   swap for snappier UX (spec written for this). Confirm.
5. On YouTube-side rejection (file passed client checks but Google rejects on
   dimensions or other reason), should the staged form data persist so the user
   can re-pick without losing the field's other dirty values? Recommendation:
   keep the staged file blob in the form, render the rejection message, do not
   clear other dirty fields. Confirm.
