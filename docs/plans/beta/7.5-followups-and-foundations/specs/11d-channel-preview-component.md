# 11d — Channel Multi-Layout Preview Component

> Sub-spec of Step 11 — Channel Edit Page Revamp. Locks the
> `ChannelPreviewComponent` that renders a Pito-built channel-page mockup at
> three viewport sizes inside a wide modal. Source of truth for the parent
> design decisions: Step 11 spec, decisions **D7** (Pito-rendered, three
> layouts, no safe zones), **D8** (videos row uses real videos or static
> JPEGs), and **D23** (wide modal with top nav `[desktop][mobile][tv]`,
> not side-by-side).

## Goal

Give the user a high-fidelity, in-app preview of how their channel page will
look on three target surfaces — **desktop** (~1280px), **mobile** (~390px),
and **TV** (1920×1080) — without leaving the Rails app and without depending
on YouTube to render the result. The preview lives inside a **wide modal**
launched from a `[preview]` button on the channel edit form. The top of the
modal carries a `[desktop][mobile][tv]` nav that switches between the three
layout panels. While the modal is open, edits to the form fields stream into
the preview via a debounced Stimulus listener, so the user sees the would-be
state of their channel page as they type.

This component is the visual heart of the Channel Edit Page Revamp: it
replaces "save and tab over to YouTube to check" with "see it inline, side by
side with the form, across all the surfaces that matter".

## Files touched

### New files

- `app/components/channel_preview_component.rb` — ViewComponent class. Accepts
  `channel:` (Channel) and `pending: {}` (Hash, optional). Exposes per-layout
  rendering helpers and the resolved attribute lookup (`pending[:title]` falls
  through to `channel.title`).
- `app/components/channel_preview_component.html.erb` — three layout panels
  (`desktop`, `mobile`, `tv`), each wrapping the same section partials sized
  to the target viewport. Only one panel is visible at a time; the others are
  `hidden` until the top-nav switches them.
- `app/javascript/controllers/channel_preview_controller.js` — Stimulus
  controller. Two responsibilities:
  1. **Top-nav toggle.** `[desktop]`, `[mobile]`, `[tv]` actions flip which
     panel has the `active` class.
  2. **Form-input listener.** Listens for `input` events on form fields tagged
     with `data-action="input->channel-preview#updatePreview"`. Debounces 300ms
     (configurable via the `debounceMsValue` Stimulus value), then re-renders
     the preview by issuing a Turbo Stream `GET` to a new endpoint
     `GET /channels/:id/preview` with the dirty form values as query params.
- `app/helpers/preview_helper.rb` — module exposing:
  - `RANDOM_VIDEO_TITLES` — frozen array of ~20 curated, generic, neutral
    video titles (e.g. "Morning routine that actually sticks", "I tried the
    cheapest mic on the market", "What we built this week"). No celebrity
    names, no clickbait, no real YouTube titles.
  - `random_video_thumbnail(seed:)` — returns a public path string like
    `/preview/video_thumbnails/thumb-03.jpg`. The `seed:` argument (e.g. the
    pseudo-video's index in the row) keeps the choice stable across re-renders
    inside one request.
  - `random_watermark_frame(seed:)` — stub for the 11e watermark preview
    sub-spec; 11d does NOT call this. Defined here so 11e can land without
    re-opening this file.
- `app/views/shared/_wide_modal.html.erb` — wide modal partial. Verified
  absent in the repo at spec time; this sub-spec creates it. The partial
  yields a body block and accepts `title:`, `id:`, and an optional `top_nav:`
  slot rendered above the body. The modal panel is max-width 1320px, capped
  at 95vh, and uses the existing modal backdrop + Stimulus controller pattern
  already shipping in `app/javascript/controllers/modal_controller.js` (if a
  modal controller exists; if not, the controller is part of this sub-spec
  and is named `wide-modal-controller.js`).
- `app/controllers/channels/previews_controller.rb` — single `show` action.
  Renders a Turbo Stream that replaces the `#channel-preview` frame inside
  the modal with the freshly-rendered component, given the query-param
  pending edits. No DB writes; this is a pure render endpoint.
- `public/preview/video_thumbnails/.keep` — directory marker. Filenames the
  user is expected to populate: `thumb-01.jpg` through `thumb-08.jpg`, each
  ~1280×720, JPEG. The spec lists them; the user supplies them out-of-band
  (or the component falls back to the `[no preview thumbnails yet]` empty
  state per D8).

### Existing files touched

- `app/views/channels/_form.html.erb` (or whatever the current edit-form
  partial is named — verify in repo before dispatch) — adds the `[preview]`
  bracketed link that opens the wide modal and tags every editable input with
  `data-action="input->channel-preview#updatePreview"` plus
  `data-channel-preview-field-param="<attribute_name>"`.
- `config/routes.rb` — adds `resources :channels do resource :preview, only:
[:show], module: :channels end` (namespaced to match the controller path).
- `app/views/channels/edit.html.erb` — mounts the wide modal partial with the
  `ChannelPreviewComponent` rendered inside it for the initial open state.

### Cross-cutting

- No locale changes — the random titles live in `PreviewHelper` as a Ruby
  constant; they are intentionally English-only test fixtures, not user copy.
- No fixtures or seed-data changes — the static thumbnails are public assets,
  not DB records.

## Acceptance

- [ ] `ChannelPreviewComponent` exists, takes `channel:` and `pending: {}`,
      and renders three sibling layout panels (`#preview-layout-desktop`,
      `#preview-layout-mobile`, `#preview-layout-tv`).
- [ ] Each layout panel renders these sections in this order: banner →
      avatar+title+handle+subscriber count → description (if present) →
      links row → videos row.
- [ ] Banner uses `channel.banner_url` (or `pending[:banner_url]`). When the
      resolved value is blank, the banner falls back to a muted placeholder
      block (background `var(--color-pane-bg-a)`, height matching the
      layout's banner spec).
- [ ] Avatar uses `channel.avatar_url` (or `pending[:avatar_url]`). When
      blank, renders a circular placeholder with the channel's first
      character (uppercase) centered in monospace.
- [ ] Title, handle, and subscriber count come from
      `pending[:title] || channel.title`, `pending[:handle] || channel.handle`,
      `channel.subscriber_count` (formatted with `number_to_human`).
- [ ] Description is rendered only if the resolved value is present; absent
      values render no element (no empty `<p>`).
- [ ] Links row reads the `links` jsonb array from
      `pending[:links] || channel.links` and renders each as a bracketed link
      `[title]` pointing at `url`. Empty array → no row at all.
- [ ] Videos row branch:
  - [ ] **Real-video branch.** When
        `channel.videos.where.not(title: nil).count >= 6`, render the first
        6 deduped (starred + latest sort already established in the codebase
        — reuse that scope).
  - [ ] **Static-thumbnail fallback.** Otherwise, render 6 pseudo-videos
        using `PreviewHelper.random_video_thumbnail(seed: i)` and
        `PreviewHelper::RANDOM_VIDEO_TITLES.sample(6)` (seeded so the choice
        is stable within a single render).
  - [ ] **Empty fallback.** If the `public/preview/video_thumbnails/`
        directory is empty (no `thumb-*.jpg`), the videos row renders the
        copy `[no preview thumbnails yet]` (bracketed, muted, single line)
        per D8.
- [ ] Layout sizing constants:
  - Desktop: max-width 1280px, horizontal padding mirroring YouTube channel
    page (≈24px), banner height ≈200px.
  - Mobile: max-width 390px (iPhone Pro standard), horizontal padding ≈16px,
    banner height ≈80px.
  - TV: 1920×1080 aspect ratio scaled down to fit the modal (transform:
    scale with `transform-origin: top left`), TV-app spacing approximation
    (banner height ≈300px scaled, larger type sizing). Reasonable guess; see
    open question Q1.
- [ ] Top nav `[desktop][mobile][tv]` lives at the top of the wide modal,
      not inside the component itself (the component renders all three
      panels; the modal chrome owns the toggle).
- [ ] Clicking a top-nav item toggles the `active` class on the matching
      panel and removes it from the others. No page reload, no Turbo
      navigation.
- [ ] Default active panel on modal open: **desktop**.
- [ ] `channel-preview` Stimulus controller debounces form-input events at
      300ms (configurable via Stimulus value) before issuing
      `GET /channels/:id/preview?<param=value>...`.
- [ ] The Turbo Stream response from `Channels::PreviewsController#show`
      replaces the `#channel-preview` frame inside the modal with a freshly
      rendered component reflecting the pending edits, **without** touching
      the form, the modal chrome, or the active top-nav selection.
- [ ] The `[preview]` button on the edit form opens the wide modal (no
      destructive action involved; standard modal-open Stimulus pattern, not
      `_action_screen.html.erb`).
- [ ] No JavaScript `alert` / `confirm` / `prompt` / `data-turbo-confirm`
      anywhere in the new files (project hard rule).
- [ ] Booleans crossing the wire (query params on the preview endpoint) use
      `"yes"` / `"no"` strings if any are introduced. (Current attribute set
      is all strings/jsonb/integers; spec calls this out preemptively for
      future-proofing.)
- [ ] Component spec covers: banner-present and banner-absent branches;
      avatar-present and avatar-absent branches; description-present and
      description-absent branches; links-present and links-empty branches;
      real-video branch and static-fallback branch; empty-thumbnails-dir
      branch.
- [ ] Component spec covers: pending-edits hash overrides each individual
      attribute (`title`, `handle`, `banner_url`, `avatar_url`,
      `description`, `links`).
- [ ] System spec covers: opening the modal from the edit form; clicking
      `[mobile]` switches the active panel; typing in the title field
      updates the preview after the 300ms debounce; closing and reopening
      the modal resets to the desktop panel.
- [ ] Request spec covers `GET /channels/:id/preview` with and without
      pending-edit query params; both return Turbo Stream responses
      (`text/vnd.turbo-stream.html`).
- [ ] `PreviewHelper` is spec'd: `RANDOM_VIDEO_TITLES` is frozen and
      non-empty; `random_video_thumbnail(seed:)` returns the same path for
      the same seed; the empty-directory branch returns `nil` (component
      then renders the empty-state copy).
- [ ] No watermark rendering anywhere in 11d. The player mockup is 11e's
      problem; the videos row in 11d shows thumbnails only.

## Manual test recipe

### Setup

```bash
bin/dev
# In another terminal, populate the preview thumbnails directory:
mkdir -p public/preview/video_thumbnails
# Drop 4–8 JPEGs named thumb-01.jpg ... thumb-08.jpg into that directory.
# Any 1280×720 placeholder will do for the manual walk.
```

### Walk

1. Visit `/channels`. Open any channel's edit page (or create a fresh one
   first if the workspace is empty).
2. Confirm the edit form now carries a `[preview]` bracketed link near the
   submit row.
3. Click `[preview]`. The wide modal opens with the **desktop** layout
   active by default. Confirm the top nav reads `[desktop][mobile][tv]`
   with `[desktop]` styled as the active item.
4. Inside the desktop panel, confirm visible sections in order: banner,
   avatar+title+handle+subscriber count, description (if your channel has
   one), links row (if your channel has any), videos row.
5. Click `[mobile]`. The desktop panel hides; the mobile panel shows. Layout
   should be narrow (~390px), banner shorter, type adjusted.
6. Click `[tv]`. TV panel shows. Wider and taller than desktop; spacing
   feels TV-app-ish (open question Q1 — flag if obviously wrong).
7. Click `[desktop]`. Returns to desktop layout.
8. With the modal still open, in the title field of the form behind the
   modal (modal does not block the form — verify the layout allows
   simultaneous interaction; if it does block, the form is accessible by
   closing the modal, editing, and reopening), edit the channel title.
   Wait 300ms. Confirm the preview's title text updates.
9. Edit the description field; wait 300ms; confirm the preview updates.
10. Clear the banner_url field; wait 300ms; confirm the banner reverts to
    the muted placeholder.
11. Close the modal (X button or backdrop click). Reopen via `[preview]`.
    Confirm the active panel resets to **desktop**.
12. For the empty-thumbnails-fallback branch: pick a channel whose `videos`
    table has fewer than 6 titled videos. Open `[preview]`. Confirm the
    videos row shows static thumbnails from `public/preview/video_thumbnails/`
    paired with titles from `RANDOM_VIDEO_TITLES`.
13. For the empty-dir branch: temporarily move every `thumb-*.jpg` out of
    `public/preview/video_thumbnails/`. Reopen `[preview]` on a low-video
    channel. Confirm the videos row reads `[no preview thumbnails yet]`.
    Restore the JPEGs.

### Teardown

No DB state changes. Remove any test channels created in step 1 via the
existing channels-bulk-delete flow.

## Cross-stack scope

- **Rails web app:** in scope. This is where the component, the controller,
  the modal partial, and the helper all live.
- **MCP:** skipped. There is no MCP tool for previewing a channel page;
  Mobile users don't need this surface. (No decision file; this is obvious
  from the surface's nature.)
- **`pito` CLI:** skipped. The CLI is a TUI and cannot render YouTube-shaped
  HTML mockups. Channel-edit-page preview is a web-only feature.
- **Cloudflare Pages website:** skipped. The website is the marketing
  surface; channel previews are an authenticated-app feature.

## Open questions

1. **TV layout dimensions and spacing.** Best-guess approximation of
   YouTube's TV-app channel page (1920×1080, larger type, generous spacing,
   banner ≈300px) versus a research pass against actual TV-app screenshots
   the user supplies. **Architect lean:** ship the guess in this dispatch;
   iterate based on user feedback after the first manual walk. The TV
   layout is the least-validated of the three and is explicitly marked as
   "reasonable approximation OK" in D7.
2. **Modal open trigger.** `[preview]` button on the edit form only, or
   also a `[preview]` link on the channel show page (`/channels/:id`)? The
   parent Step 11 spec is explicit about the edit form; the show page is
   not mentioned. **Architect lean:** edit form only for 11d; revisit if
   the user wants a read-only preview from the show page after the first
   round of dogfooding.
3. **Mobile vs desktop default on modal open.** Which layout is active
   when the modal first opens? **Architect lean:** desktop. Matches the
   likely user posture (dogfooding on a laptop) and the largest panel is
   the most visually informative.
4. **Pending-edits Stimulus event cadence.** Three options:
   - Input-by-input live update (every keystroke triggers a Turbo Stream
     fetch). Most responsive, potentially janky under fast typing.
   - Debounced 300ms (this spec's default). Smooth, costs at most one
     fetch per typing burst.
   - On-save (form submit). Least surprising, but defeats the purpose of
     an in-flight preview.
     **Architect lean:** debounced 300ms.
5. **Brand-account watermark preview.** The 11e watermark preview sub-spec
   handles the video-player mockup separately. Confirm 11d does NOT try to
   render the watermark in any of its three layouts. **Architect lean:**
   confirmed — 11d renders thumbnails only; the player mockup with the
   watermark composited on top is 11e's territory.
6. **`PreviewHelper` random-title list curation.** ~20 generic neutral
   titles seems right; user may want to expand or trim the list. The list
   lives in code, not the DB, so curation is a quick PR rather than a UI
   surface. **Architect lean:** ship with a starter list; iterate as the
   user dogfoods.
7. **Wide modal partial naming.** `shared/_wide_modal.html.erb` versus a
   namespaced `previews/_modal.html.erb`. The shared partial assumes the
   wide modal is a reusable primitive — 11e and future preview surfaces
   will reuse it. **Architect lean:** `shared/_wide_modal.html.erb` to
   make the reuse explicit.
