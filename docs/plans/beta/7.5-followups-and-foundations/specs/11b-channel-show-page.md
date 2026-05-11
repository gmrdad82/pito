# Phase 7.5 — Step 11b — Channel Show Page Revamp

> Sub-spec of Step 11 — Channel Management + Multi-Layout Preview.
> Parent: [`11-channel-management-and-preview.md`](./11-channel-management-and-preview.md).
> Depends on 11a (schema + sync) — every column this page renders
> (`title`, `handle`, `description`, `banner_url`, `avatar_url`,
> `links`, `subscriber_count`, `view_count`, `video_count`,
> `hidden_subscriber_count`, `published_at`) ships in 11a.
> Locked decisions inherited: D1, D2, D8, D12, D13, D18, D20, D23.

## Goal

Replace the placeholder channel detail surface at `/channels/:slug` with
the full channel show page locked by the user's revamp directive. The
page renders cached YouTube channel data (banner, avatar, title, handle,
description, links) as a read-only display, exposes two outbound
deep-links (YouTube channel page + YouTube Studio), and surfaces two
follow-up rows beneath the detail pane: an analytics summary and a
videos pane (starred-first, then latest, capped at 30) that hands off to
the existing `/videos?channel=<slug>` picker via a `[see all]` link.

This sub-spec is **pure view work** — no controller, model, migration,
or service changes. The data is already on the `Channel` record after
11a. The output is a refactored `app/views/channels/show.html.erb` plus
three extracted partials, a thin `channels_helper.rb`, a thin
`youtube_helper.rb`, and the matching RSpec sweep.

Why it matters: the current show page is a two-pane URL+videos
placeholder from the Phase 4 channel-revamp era. With 11a's columns
landed, the user expects the page to feel like an actual channel
overview — banner up top, identity block, outbound links, then
analytics, then a videos preview — before 11c's edit form ships.

## Scope boundary

### In-scope

- Replace `app/views/channels/show.html.erb` with the new vertical
  layout (three pane rows: detail, analytics, videos).
- Extract three partials under `app/views/channels/`:
  `_banner.html.erb`, `_links.html.erb`, `_videos_pane.html.erb`.
- Add `app/helpers/channels_helper.rb` (new file) with rendering helpers
  for the detail block (formatted subscriber count, hidden-subscriber
  treatment per D12).
- Add `app/helpers/youtube_helper.rb` (new file) with two outbound URL
  builders:
  - `youtube_channel_url(channel)` →
    `https://www.youtube.com/channel/<youtube_channel_id>` (derived from
    `channel.channel_url` — Channel already locks the canonical
    `/channel/UC…` form via `CHANNEL_URL_REGEX`).
  - `youtube_studio_url(channel)` →
    `https://studio.youtube.com/channel/<youtube_channel_id>`.
- Preserve existing chrome unchanged in placement (only relabel where
  noted): breadcrumb, `[+]` add-pane button, `[e]` edit link, `[sync]`
  action, `[-]` destructive deletion.
- Add the **diff-check banner slot** (D20) as a Turbo-frame placeholder
  named `channel_diff_banner` immediately under the H1, so 11i can
  inject the "YouTube has X newer values" banner without re-touching
  this view. Empty frame in 11b; populated by 11i. Frame markup only —
  no controller, no fetch.
- Friendly-URL routing already works (`Channel#to_param` returns the
  UC-id slug; the existing `friendly.find` chain is unchanged).
- Empty states for every pre-sync nullable field (banner, avatar, title,
  handle, description, links, stats). Render muted placeholders, never
  500.

### Out of scope

- `[edit]` form rendering (sub-spec 11c).
- The wide-modal preview component (sub-spec 11d) — the `[preview]`
  affordance the parent spec mentions belongs to 11c's banner field;
  11b's banner is purely a cached image with a muted placeholder when
  null.
- The `/channels/:slug/diff` page (sub-spec 11i) — 11b only ships the
  empty `channel_diff_banner` Turbo frame so 11i can stream the banner
  into it later.
- Calendar reminder affordance (sub-spec 11h).
- Change-history list (sub-spec 11g).
- Analytics chart rendering itself. The analytics row in 11b is a
  summary numbers block + an outbound link to the existing analytics
  surface (current path `/channels/:slug/analytics` if it exists, else
  flagged as Q3 below). 11b does NOT introduce inline charts; the open
  question below asks whether to add a sparkline.
- Avatar `[edit]` affordance (D2 — display-only pending verification).
- Any modification to `ChannelsController#show` beyond view-layer
  changes. The action already loads `@channel` and `@available_channels`
  and that is sufficient for 11b's needs.

## Files touched

**Views:**

- `app/views/channels/show.html.erb` — rewritten to the new layout.
- `app/views/channels/_banner.html.erb` — new partial. Renders
  `banner_url` `<img>` or the muted placeholder block, plus the avatar +
  title + handle + outbound-links cluster overlaid/adjacent (the impl
  agent picks; see Manual test recipe for the visual target).
- `app/views/channels/_links.html.erb` — new partial. Iterates
  `channel.links` (jsonb array of `{ title, url }`); renders each as a
  bracketed link `[<title>]` pointing at `<url>`. Empty-state: `<p
  class="caption">no links yet.</p>` when the array is empty or nil.
- `app/views/channels/_videos_pane.html.erb` — new partial. The
  starred-first + latest-30 list with the `[see all]` link.

**Helpers:**

- `app/helpers/channels_helper.rb` — new file. Methods:
  - `formatted_subscriber_count(channel)` — returns `"Hidden"` when
    `channel.hidden_subscriber_count?` is true; otherwise
    `number_with_delimiter(channel.subscriber_count)` when present;
    otherwise the muted placeholder string `"—"` (em dash).
  - `formatted_view_count(channel)` — `number_with_delimiter` or `"—"`.
  - `formatted_video_count(channel)` — `number_with_delimiter` or `"—"`.
  - `channel_display_title(channel)` — returns `channel.title` when
    present, else a muted placeholder `"untitled channel"` for use in
    the H1.
- `app/helpers/youtube_helper.rb` — new file. Methods:
  - `youtube_channel_id(channel)` — extracts the `UC…` id from
    `channel.channel_url` via the existing
    `Channel::CHANNEL_URL_REGEX`-adjacent helper; returns `nil` if the
    URL is unexpectedly malformed (defense-in-depth — the regex on the
    model should already prevent this, but the helper does not crash).
  - `youtube_channel_url(channel)` —
    `"https://www.youtube.com/channel/#{youtube_channel_id(channel)}"`.
    Returns `nil` if the id is nil.
  - `youtube_studio_url(channel)` —
    `"https://studio.youtube.com/channel/#{youtube_channel_id(channel)}"`.
    Returns `nil` if the id is nil.

**No controller, model, migration, JS, or CSS files in scope.** The
existing `.pane`, `.pane--standalone`, and `.pane-row` primitives carry
all the layout weight. Any net-new style that creeps in is a signal that
the impl agent has drifted out of scope and should stop.

**Specs:**

- `spec/views/channels/show.html.erb_spec.rb` — view spec, rendering
  matrix (happy / sad / edge / flaw).
- `spec/views/channels/_banner.html.erb_spec.rb` — partial spec.
- `spec/views/channels/_links.html.erb_spec.rb` — partial spec.
- `spec/views/channels/_videos_pane.html.erb_spec.rb` — partial spec.
- `spec/helpers/channels_helper_spec.rb` — helper spec.
- `spec/helpers/youtube_helper_spec.rb` — helper spec.
- `spec/requests/channels_show_spec.rb` (or extend the existing
  `spec/requests/channels_spec.rb` if there is one — the impl agent
  picks the lowest-friction merge) — request spec.
- `spec/system/channel_show_journey_spec.rb` — single thin system spec
  for the critical journey (see Spec sweep below).

## Layout (locked)

Three pane rows stacked vertically, matching the project's
`.pane-row` + `.pane` / `.pane--standalone` primitives (see
`docs/agents/architect.md` rule C):

```
[breadcrumb] [+] [e] [sync] [-]

<h1>channel <title or "untitled channel"></h1>
[turbo-frame id="channel_diff_banner"][/turbo-frame]   ← empty in 11b

.pane-row
  .pane.pane--standalone (full width, row 1 — detail)
    banner partial
      ├ banner image (or muted placeholder block)
      ├ avatar (or muted placeholder circle)
      ├ title
      ├ handle (@handle, italic muted if missing)
      ├ [youtube channel ↗] [youtube studio ↗]   ← outbound links
      ├ description (or muted "no description yet.")
      └ links partial (jsonb iteration)

.pane-row
  .pane.pane--standalone (full width, row 2 — analytics)
    subscribers · views · videos (three inline stat cells)
    [full analytics] outbound link  ← see Q3 / Open questions

.pane-row
  .pane.pane--standalone (full width, row 3 — videos pane)
    <h2>videos (<total count>)</h2>
    [see all] → /videos?channel=<slug>
    starred-first list, then latest, capped at 30 total
```

Each `.pane-row` carries its own zebra index automatically (per project
convention — `.pane:nth-child(even)` only fires inside multi-pane rows,
not across rows; the impl agent confirms the existing CSS reads the
intended way against three standalone single-pane rows).

The order of the ten elements inside the detail pane matches the user's
locked directive (banner → avatar → title → handle → YT link → Studio
link → description → links). The analytics + videos sections are
explicitly **separated into their own rows** beneath the detail pane per
the recent UX rule (parent directive, item 9).

## Outbound link details

Both outbound links open in a new tab with `target="_blank"
rel="noopener noreferrer"` (matching the existing URL row's link pattern
in the legacy show view). Labels use the bracketed convention with no
inner padding spaces per `docs/agents/architect.md` rule A:

- `[youtube channel]` → `youtube_channel_url(@channel)`
- `[youtube studio]` → `youtube_studio_url(@channel)`

No trailing icon glyph; the existing visual style relies on
bracket-and-label only (`docs/design.md`).

## Videos pane behavior (locked)

```ruby
videos = @channel.videos
  .order(Arel.sql("star DESC, COALESCE(published_at, created_at) DESC"))
  .limit(30)
```

- `star DESC` puts starred rows first (NULLs and `false` sort after
  `true` under Postgres default-ascending semantics; `DESC` flips that
  so starred rows lead).
- `COALESCE(published_at, created_at) DESC` falls back to `created_at`
  when 11a's Phase 8 sync has not yet populated `published_at` on the
  video. (Schema reminder: Video gained `title` in 11a; `published_at`
  is **not** part of this spec's 11a scope per parent spec — but the
  pane already needs a stable ordering today. Using
  `COALESCE(published_at, created_at)` lets the pane work both pre- and
  post-Phase-8.)
- `limit(30)` caps the list at 30 total rows.

Each row renders: video id (linked to `video_path(video)`), YouTube id,
title (or `"untitled"` per D1 when `title` is nil), and a star indicator
when `star` is true. The existing `sortable-table` Stimulus controller
+ `SortableHeaderComponent` pattern from the current show view is
preserved — columns are sortable client-side.

`[see all]` link target: `videos_path(channel: @channel.to_param)`.
This filter is already implemented in `VideosController#index` per the
existing show view's comment block (no controller change needed in
11b). The link uses the bracketed convention: `[see all]`.

Empty state: when `@channel.videos` is empty, render `<p
class="caption">no videos yet.</p>` (matches the existing empty state in
the legacy show view).

## Empty-state matrix (locked)

| Field                      | Nil/empty rendering                                       |
| -------------------------- | --------------------------------------------------------- |
| `banner_url`               | Muted `<div>` block at banner's aspect ratio, "no banner" |
| `avatar_url`               | Muted circular `<div>` placeholder, "no avatar"           |
| `title`                    | H1 reads "untitled channel"; detail row shows em dash     |
| `handle`                   | Detail row shows "@—" muted, or omits the row entirely    |
| `description`              | `<p class="caption">no description yet.</p>`              |
| `links` (jsonb empty / nil) | `<p class="caption">no links yet.</p>`                    |
| `subscriber_count`         | em dash `"—"` unless `hidden_subscriber_count?` → "Hidden" |
| `view_count`               | em dash `"—"`                                             |
| `video_count`              | em dash `"—"`                                             |
| `published_at`             | em dash `"—"` (only shown if exposed in detail row)       |

Placeholders use the existing `text-muted` class. No new CSS.

## Friendly URLs

Routes already use `Channel#to_param`; 11b changes nothing here. The
parent directive's path `/channels/:slug` resolves through the existing
`Channel.friendly.find` chain in `ChannelsController#show`. The page
title and breadcrumb continue to read `channel #<id>` until/unless the
user requests a slug-first label in a follow-up.

Note: the legacy show view's breadcrumb shows `channel #<id>` because
title is not populated pre-11a. With 11a's `title` column now
populated, the impl agent updates the breadcrumb / page label to use
`channel_display_title(@channel)` (returns the title when present,
"untitled channel" when nil). The breadcrumb's clickable parent
("channels") is unchanged.

## Acceptance

- [ ] `/channels/:slug` renders the three pane rows in order: detail,
      analytics, videos.
- [ ] Detail pane renders banner → avatar → title → handle → `[youtube
      channel]` → `[youtube studio]` → description → links in that
      order.
- [ ] Banner partial renders `<img src="<banner_url>">` when present;
      renders a muted placeholder block when `banner_url` is nil.
- [ ] Avatar renders `<img>` when `avatar_url` present; muted
      placeholder when nil. **No `[edit]` affordance** (D2).
- [ ] Title row renders `channel.title` or "untitled channel"
      placeholder.
- [ ] Handle row renders `channel.handle` or muted placeholder.
- [ ] `[youtube channel]` link points at
      `https://www.youtube.com/channel/<UC-id>`, opens in new tab.
- [ ] `[youtube studio]` link points at
      `https://studio.youtube.com/channel/<UC-id>`, opens in new tab.
- [ ] Description block renders `channel.description` (text-only — see
      Q4) or "no description yet." caption when blank.
- [ ] Links partial iterates the jsonb array; renders one bracketed
      link per entry; renders "no links yet." caption when empty.
- [ ] Analytics row renders subscriber / view / video counts using the
      helper-formatted values; `"Hidden"` when
      `hidden_subscriber_count?`; em dash when count is nil.
- [ ] Videos pane orders starred first, then latest by
      `COALESCE(published_at, created_at) DESC`, capped at 30.
- [ ] `[see all]` link points at `videos_path(channel:
      @channel.to_param)`.
- [ ] Existing chrome preserved: breadcrumb, `[+]` add-pane, `[e]`
      edit, `[sync]`, `[-]` destructive deletion. No relabeling beyond
      noted exceptions.
- [ ] Empty Turbo frame `channel_diff_banner` present under H1 (so 11i
      can stream into it later).
- [ ] No 500s on a channel with every nullable field nil (the pre-sync
      state).
- [ ] No `confirm()` / `alert()` / `data-turbo-confirm` added (project
      hard rule).
- [ ] Bracketed labels use no inner padding spaces — `[youtube
      channel]` not `[ youtube channel ]` (project rule A).
- [ ] Description rendering passes Loofah sanitization — raw HTML /
      `<script>` tags from the description column do not execute (XSS
      defense per D2 + project hardening posture).
- [ ] Spec sweep covers: view, all three partials, both helpers, the
      request spec (happy / sad / edge / flaw), one system journey
      spec. RSpec green.

## Manual test recipe

Setup:

```bash
bin/dev    # start app
bin/rails console
```

In the console, hydrate a channel with full fields:

```ruby
c = Channel.first
c.update!(
  title: "Pito Test Channel",
  handle: "@pitotest",
  description: "A devlog about building Pito. Multi-line\nworks fine.",
  banner_url: "https://yt3.googleusercontent.com/some-real-banner.jpg",
  avatar_url: "https://yt3.googleusercontent.com/some-real-avatar.jpg",
  links: [
    { "title" => "GitHub", "url" => "https://github.com/example" },
    { "title" => "Blog", "url" => "https://example.com/blog" }
  ],
  subscriber_count: 12345,
  view_count: 678901,
  video_count: 42,
  hidden_subscriber_count: false,
  published_at: 3.years.ago
)
```

Then visit `/channels/<c.to_param>` and verify:

1. The page H1 reads "channel Pito Test Channel".
2. The detail pane renders banner → avatar → title → handle → `[youtube
   channel]` → `[youtube studio]` → description → links cluster.
3. `[youtube channel]` opens
   `https://www.youtube.com/channel/<UC-id>` in a new tab.
4. `[youtube studio]` opens
   `https://studio.youtube.com/channel/<UC-id>` in a new tab.
5. The analytics row shows `subscribers: 12,345 · views: 678,901 ·
   videos: 42` (or equivalent visual treatment).
6. The videos pane lists up to 30 videos for the channel, starred
   first.
7. `[see all]` links at `/videos?channel=<c.to_param>` and the picker
   page loads pre-filtered.

Pre-sync test (every nullable column NULL):

```ruby
c2 = Channel.create!(channel_url: "https://www.youtube.com/channel/UCqqqqqqqqqqqqqqqqqqqqqq")
```

Visit `/channels/<c2.to_param>`. Page must render without 500. Verify:

- H1 reads "channel untitled channel".
- Banner area shows muted "no banner" placeholder.
- Avatar shows muted "no avatar" placeholder.
- Description shows "no description yet." caption.
- Links shows "no links yet." caption.
- Analytics row shows em dashes for sub / view / video counts.
- Videos pane shows "no videos yet." caption.

Hidden-subscriber test:

```ruby
c.update!(hidden_subscriber_count: true)
```

Visit the show page. Subscribers cell reads "Hidden" instead of the
number.

XSS test:

```ruby
c.update!(description: "<script>alert('xss')</script><b>bold</b>", title: "<img onerror=alert(1) src=x>")
```

Visit the show page. The `<script>` tag must not execute; the page must
not pop a JS dialog; the literal text appears escaped (Loofah strips or
escapes the tag).

## Cross-stack scope

| Surface              | In scope? | Notes                                                                                  |
| -------------------- | --------- | -------------------------------------------------------------------------------------- |
| Rails web (HTML)     | YES       | Primary surface — every change lands here.                                              |
| Rails JSON (decorator) | NO      | `ChannelDecorator#as_detail_json` already exposes channel fields; no spec change.       |
| MCP                  | NO        | No MCP tool touches `/channels/:slug`. `get_channel` is parent-spec future work.        |
| Pito CLI             | NO        | CLI renders its own channel detail screen; mirroring is a separate follow-up.           |
| Website              | NO        | Marketing site does not depend on the show page.                                        |

## Spec sweep

Per `docs/agents/architect.md` rule D (spec pyramid) and the project's
"spec exhaustively" memory:

1. **View spec** (`spec/views/channels/show.html.erb_spec.rb`):
   - **Happy** — all columns populated. Asserts every section renders,
     outbound links carry the right `href`, videos pane renders rows.
   - **Sad** — every nullable column is nil. Asserts no 500, every
     placeholder fires.
   - **Edge** — empty `links` jsonb array (`[]` vs `nil` — both render
     "no links yet."). Edge: `video_count` is 0 but `videos.count` is 3
     (mismatch from a partial sync — the videos pane uses the actual
     `videos` association, not the cached column).
   - **Flaw** — XSS attempt via `title` and `description` columns;
     Loofah escapes/strips. The rendered HTML does not contain a
     functional `<script>` tag.

2. **Partial specs**:
   - `_banner.html.erb_spec.rb` — `banner_url` present vs nil; same for
     `avatar_url`.
   - `_links.html.erb_spec.rb` — 0 / 1 / 5 entries; entry with malformed
     URL (defense — already validated server-side, but the view must
     not crash on stale data).
   - `_videos_pane.html.erb_spec.rb` — 0 / 1 / 30 / 31 videos (31 caps
     to 30); starred-first ordering; `[see all]` link target.

3. **Helper specs**:
   - `channels_helper_spec.rb`:
     - `formatted_subscriber_count` — hidden → "Hidden", numeric →
       formatted, nil → em dash.
     - `formatted_view_count` / `formatted_video_count` — numeric vs
       nil.
     - `channel_display_title` — title present vs nil.
   - `youtube_helper_spec.rb`:
     - `youtube_channel_id` — valid UC-URL → extracts id; malformed
       URL → nil.
     - `youtube_channel_url` — valid → expected URL; malformed → nil.
     - `youtube_studio_url` — valid → expected URL; malformed → nil.

4. **Request spec** (`spec/requests/channels_show_spec.rb` or extend
   `channels_spec.rb`):
   - GET `/channels/:slug` 200 happy (populated).
   - GET 200 sad (every column nil).
   - GET 200 edge (empty links jsonb).
   - GET 200 flaw (XSS in title + description — body does not contain
     `<script>`).
   - GET via integer id redirects to canonical slug URL (existing
     `redirect_to_canonical_slug!` behavior — assert unchanged).
   - GET unknown slug → 404 (existing behavior — assert unchanged).

5. **System spec** (`spec/system/channel_show_journey_spec.rb`):
   - From `/channels` (picker), click into a channel.
   - Assert all sections render (detail, analytics, videos).
   - Click `[see all]` in the videos pane.
   - Assert landing on `/videos?channel=<slug>` with the channel filter
     chip visible.
   - Thin — one happy-path journey only; covers the load-bearing
     integration of view + helper + filter.

No new component spec (no ViewComponent introduced — partials only). No
new model / service / job / lib / validator / MCP-tool / routing spec
(routes unchanged).

## Open questions

These are intentionally left for the master agent to resolve before
dispatching the rails-impl agent on 11b.

**Q1 — Sparkline in the analytics row, or pure summary numbers?**

Option A: pure summary — subscribers / views / videos counts only, plus
`[full analytics]` link to `/channels/:slug/analytics`. Cheapest; ships
on day one.

Option B: tiny sparkline inline — e.g., subscriber growth across the
last 30 days drawn with Chartkick or a CSS-only mini-bar pattern.
Heavier; depends on whether `channel_dailies` already carries the rows
(it does per Phase 13.1, but the chart partial is a new asset).

Default if the master agent doesn't answer: Option A. Sparkline upgrades
to a follow-up.

**Q2 — Videos pane dedup behavior.**

When a starred video is also among the latest, do we (a) show it twice
(once in the starred block, once in the latest block) — visually
useless, but matches the literal "starred first, then latest"
directive; or (b) dedupe so the starred row only appears once at the
top, and the latest list excludes already-listed starred rows?

Default if unanswered: Option (b) dedupe — the SQL above
(`ORDER BY star DESC, ...`) naturally produces this: starred rows
appear first, the rest fill the remaining slots up to 30. No video
appears twice.

**Q3 — Banner pre-sync rendering.**

Until 11f's sync populates `banner_url`, every existing channel has
`banner_url = nil`. Options:

Option A: muted gray block sized to the YouTube banner aspect ratio
with a centered `"no banner"` caption. Same look as a missing image
state elsewhere in Pito.

Option B: hide the banner section entirely (skip the `<div>`) until
`banner_url` populates.

Option C: render a single-color CSS block in `--color-pane-bg-a` so the
section still occupies vertical space but feels intentional.

Default if unanswered: Option A. Keeps layout stable across pre- and
post-sync states.

**Q4 — Description rendering: plain text + auto-link, or markdown?**

YouTube's channel descriptions are plain text with URL auto-linking
(YouTube renders bare URLs as links). Options:

Option A: render as plain text via `simple_format` + Rails'
`auto_link` (or an equivalent helper) for URLs. Preserves line breaks,
hyperlinks bare URLs, Loofah-strips any HTML the user pasted in.

Option B: render as raw text (just `<%= sanitize @channel.description
%>` with `<br>` for newlines). No auto-linking.

Option C: render as markdown via Redcarpet / kramdown. Maximum fidelity
to creators who use Notion-style descriptions; biggest surface for
parser bugs.

Default if unanswered: Option A. Matches YouTube's actual behavior
(auto-linked plain text) and uses Rails primitives only (no new gem).

**Q5 — Analytics row landing page.**

The acceptance and layout assume `[full analytics]` links to
`/channels/:slug/analytics`. Verify the route exists today (Phase 13.1
should have shipped it). If it does not, the link target needs to
change or be deferred.

Default if unanswered: assume the route exists; impl agent verifies and
flips to "deferred — no `[full analytics]` link in 11b" if the route is
missing.

**Q6 — Avatar placement.**

The user's directive lists banner → avatar → title as elements 1 → 2 →
3. Implementation interpretation: the avatar visually overlaps the
banner (YouTube's convention — avatar circle anchored at the
banner's bottom-left), or sits in its own row beneath the banner?

Default if unanswered: avatar in its own row beneath the banner. Lower
CSS risk; matches the "linear list of fields" feel of the rest of the
detail pane. The overlap pattern can land in 11d's preview component
where YouTube fidelity matters more.
