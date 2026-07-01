# Changelog

All notable changes to PITO are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [0.8.5] — Unreleased

A broad follow-up to **analtics**: a full `show channel` surface, sharper `sync`
and `analyze` reply flows, named conversations, a faster/cleaner notifications
panel, a self-hosted typeface, and an exhaustive dispatcher-recognition spec net
that hardens every verb/keyword combination across the slash, hashtag, and chat
stacks. (Bespoke analytics view components close out the tag.)

### Added

- **Shareable links are clickable + one-click copy** — the `share` reply now renders
  the public link as a real clickable link (opens in a new tab, action-styled) with
  a copy-to-clipboard icon right beside it, so you can open or grab it instantly.

- **`analyze` retention chart** — the `:enhanced` analyze card's audience-retention
  metric (lifetime, per-video) now renders as a real **area chart** — same reveal
  animation and shimmer as the Views chart — instead of a placeholder, filled by its
  own dedicated background request. Its caption is a distinct witty line reporting the
  average retention and how it benchmarks.

- **`analyze` day-of-week heatmap** — the `:enhanced` analyze card now leads with a
  **day-of-week heatmap**: seven equal-width, full-height braille bars (Mon→Sun),
  each tinted on the green→red health ramp by that weekday's average views over the
  channel's lifetime (busiest weekday green, quietest red), with the shared pito-blue
  shimmer swept over it. The caption calls out your busiest posting day. Works on
  vid, channel, and game scopes.

- **`analyze` comments chart** — comments moved from a plain scalar to a real **area
  chart** in the `:enhanced` card (last metric), on vid, channel, and game.

- **Per-platform release dates — PlayStation, Switch, Xbox, and Steam** — a game's
  upcoming release is now tracked **per platform** instead of as one blurry date.
  `show game` shows a release date per platform, grouped by date: platforms sharing
  a date collapse to one line with all their logos, and platforms with different
  dates each get their own line with their own logo (e.g. **PlayStation + Steam**
  on July 31, **Switch** in Q3). The release countdown now fires **one reminder per
  distinct date, naming which platform is releasing** ("… on PlayStation + Steam in
  3 days"). Xbox joins as a first-class platform (logo + grouping, catching Xbox One
  / Series X|S / 360). No other tool tracks per-platform release dates for a
  creator's slate. **Backfill:** existing games pick up per-platform dates on their
  next IGDB sync — to refresh everything now, run
  `Game.find_each { |g| GameIgdbSync.perform_later(g.id) }` from the console.

- **Missing-image placeholders you can click to sync** — every entity image
  (channel banner & avatar, video thumbnail, game cover — every size and every
  card) now falls back to a muted click-to-sync placeholder when nothing is
  attached, instead of a bare `?` or a "No cover" line. It's a rectangle for
  banners / thumbnails / covers, a circle for avatars, showing a centered
  **"No image." + sync** (auto-hidden on boxes too small to read, like tiny
  avatars). The **whole box is clickable**: one click types the exact sync
  command for that entity and runs it (a real Enter keypress) — so you go from
  "there's no art here" to fetching it in one tap. A new `Pito::ImageRender`
  service owns the image-or-placeholder decision, so no card hand-rolls it.
- **Direct `sync game #id` and `sync channel @handle`** — game sync used to be
  reply-only and `sync channel` only took the shift+tab scope. Now both work as
  direct id/handle commands (mirroring `show game #id` / `show channel @handle`),
  which is what the new image placeholders click to run. `sync channel @handle`
  scopes to that one channel (overriding the shift+tab scope); `sync vid #id`
  is unchanged.

- **`show game` channel coverage + recommendation** — the channel-matches card is now
  two columns: the left shows this game's coverage **distribution across your channels**
  (offset bars weighted by linked videos, views, and lifetime watch-time), the right shows the top-5 channel
  **recommendation** (avatar + fit score) — the same channels, side by side. The
  distribution streams in progressively (a no-data canvas until the numbers land);
  the recommendation renders instantly. No other tool shows cross-channel game coverage.

- **Auto-purge of unnamed conversations** — a nightly job deletes conversations
  that you never named (still on the default `Unnamed N` title) once they've had no
  activity for **30 days**; anything you actually titled — even a name that starts
  with "Unnamed" — is kept and only ever deleted by you. It deletes one at a time
  through the same path as the sidebar `dd` shortcut (no bulk lock), and the
  `/resume` sidebar now shows an ironic heads-up under "n rename · dd delete".

- **Image masters + on-demand variants** — the channel banner & avatar, video
  thumbnail, and game cover art now store the **original, unprocessed** source image
  as the master, with the display sizes derived as named ActiveStorage variants
  (banner 450×253 · avatar 120/60 · thumbnail 450×253 · cover 450w detail + 180×240
  strip — the strip is now 1:1 with its display, no browser downscale). Re-syncing a
  channel / vid / game fetches a fresh master; **`rake pito:images:regenerate`**
  re-derives every variant from the masters (run after a re-sync, or when sizes
  change — safe in the Docker CLI / production).

- **`analyze` fills metric-by-metric** — the `analyze` `:system` and `:enhanced`
  cards now render every metric cell up front in a loading state, then **fan out one
  dedicated background request per metric** (each its own YouTube call), swapping each
  chart / heart / bar / scalar in **independently** as it lands. A failing or
  empty metric shows its no-data placeholder without blocking the rest; the card's
  thinking block holds until **every** metric is in. (`:system` uses your shift+space
  period; `:enhanced` is lifetime.)

- **Progressive at-a-glance analytics** — the `show vid` / `show game` /
  `show channel` glance now renders **all metric cells up front in a loading
  state** (dotted-paper canvas + metric name + a small dots-loader), then **fans
  out one dedicated background job per metric**. Each metric makes its **own
  YouTube request** for just that metric (scalar + day-series) and **swaps its own
  cell in independently** the moment it lands — so a slow or failing metric never
  blocks the rest (a failed one shows a dash, the others still fill). The card's
  thinking block stays up until **every** metric has landed, then the whole message
  persists in its filled state. All glance metrics are **lifetime/all-time** (the
  intro copy now says so). A metric whose request **fails, is quota-limited, or
  comes back with no data** keeps its dotted-paper no-data canvas and shows **n/a**
  in place of a value — the others still fill, and that state persists on refresh.

- **Channel banner on `show channel`** — PITO now caches its own copy of the
  YouTube channel banner during sync: it fetches the **original 2560×1440** banner
  (the raw URL serves only a 512×288 default) and downscales it to 374×210 — the
  same 16:9 box as a video thumbnail (both 16:9, so nothing is cropped), served
  from our host, never hotlinked. On the `show channel` card the banner takes the
  top-left spot, and the **avatar always lives in the kv-table** (above the handle)
  as a small **120×120 variant** shown at 60px (a real ActiveStorage variant, not a
  CSS-scaled full image). A channel with **no banner** leaves the top-left spot
  empty (the avatar is never shown on the left). The banner and avatar are
  **re-saved on sync only when the image actually changed** (digest-gated), and the
  small avatar variant is derived from the attached avatar — so it shows even on a
  channel that hasn't re-synced since.
- **`show game` split into three reply-able cards** — the recommendations now
  arrive as separate `:enhanced` messages — **similar games**, **linked videos**
  (when any), and **channel matches** — in that order under the detail card, each
  with its own thinking block. Each is context-repliable: reply `show #<id>` on
  similar games → `show game`, on linked videos → `show vid` (plus `unlink #<id>`
  to unlink that video from the game), and `show @<handle>` on channels →
  `show channel`.
- **Thinking blocks on `sync` results** — every `sync` outcome (`sync channel`,
  `sync channel videos`, `sync vid`, `sync videos`, `sync game`) now shows a
  **thinking indicator** while it runs and resolves into a witty, shimmered intro
  line (50-variant `sync.intro` copy + a new `syncing` thinking dictionary) — so
  async results no longer pop in unannounced.
- **Analytics likes HEARTS** — the `analyze` `:system` grid renders the **Likes vs
  Dislikes** metric as braille **hearts** filled bottom→top to the lifetime
  approval score (likes/(likes+dislikes)%): vid/game shows a **subject heart**
  (red) beside the **channel-average heart** (purple); channel shows one. The
  hollow rim above the fill reads as the remaining dislikes. The hearts reuse the
  exact area-chart container chrome (so they flow identically in portrait and
  landscape), carry a thumbs-up/down legend, and a witty 50-variant caption.
- **Analytics area charts — Views, Watched Hours, Subs, Avg View Duration, and Avg Retention** — the `analyze`
  `:system` grid now shows **five** Studio-style **braille area charts** side-by-side at **channel / video / game**
  level, each a ~thumbnail-wide 16:9 widget with a **subscriber-aware red→green
  health gradient**, discrete tick values, a pito-blue shimmer with a distinct
  per-metric phase offset so the five never pulse in sync, its **own** bottom-up
  reveal animation (independent of the `/config` fx effect), and a witty caption.
  Views / Watched Hours / Subs captions carry a filled **trend triangle** (▲/▼/–)
  vs the prior window.
  **Avg View Duration** uses adaptive bucketing (daily ≤30 days, weekly 31–90, monthly
  >90) with per-bucket Σ(estimated_minutes_watched×60)/Σ(views); ticks and caption
  values show **M:SS**; health target is 2:00 (120 s). No trend triangle.
  **Avg Retention** is always **lifetime** (the shift+space period window is
  ignored); the x-axis shows video-position percentages (0%→100%) rather than day
  indices; vid level = the video's own audience-retention curve; game/channel =
  **views-weighted average** across linked/all videos fetched and cached per-video
  in `AnalyticsPrimitive` (report: "retention"); caption shows **M:SS (XX.X%)**
  plus a cyan "lifetime" reference token; health target is 50%. No trend triangle.
  The five chart metrics are ordered first in the `:system` grid
  (`views, watched_hours, subs, avg_view_duration, avg_viewed_pct`); remaining
  scalars keep the `0`/`1` scaffold display until each is built.
- **Glance sparklines** — the `show vid` / `show game` / `show channel`
  `:enhanced` glance now renders a **2-row braille mini-series above the scalar**
  for its four time-series metrics (**views, watched hours, net subs, likes**),
  fetched as day-series alongside the period totals (new
  `Pito::Analytics::GlanceSeries`; `likes` added to the daily report). The scalars
  are unchanged; metrics with no series stay scalar-only. The sparkline is a flat
  **fg-default** line (no health gradient) under the shared pito-blue chart-viz
  shimmer, chart-width, with no ticks/legend/caption/axis — and an empty or
  all-zero series still floors a minimal baseline row so the cell always shows a
  line.
- **Analytics bar breakdowns** — the `analyze` grid renders share-of-audience
  metrics as braille **horizontal bar groups** (new
  `Pito::Analytics::Metric::BarChartComponent` + `Pito::Analytics::Breakdown`):
  **Subscribed** (subscribed vs not — `:system`) and **Devices**, **Geography**
  (top 5 countries), **Gender**, and **Age** (top 5 buckets) in `:enhanced`. Each
  is 1–5 group-centered bars (full braille fill in the bar's colour + the heart's
  dim "missing" remainder, a minimum sliver so tiny shares still show), on the
  same canvas/dotted-paper/reveal/pito-blue-shimmer as the area chart, with a
  legend (label + %) below. Shares aggregate from per-video dimension primitives
  (views-summed for subscribed/devices/geography; `viewerPercentage`-renormalised
  for gender/age) and are persisted so a `with`/`without` reply re-renders without
  re-fetching.
- **`show channel`** — a full channel surface: a `:system` detail card (with
  last-sync time and a trimmed linked-game card), an `:enhanced` repliable vids
  list, and an `:enhanced` channel analytics glance. Channels now carry a
  `description` synced from the YouTube snippet.
- **Named conversations** — `/new <name>` opens a titled conversation and
  `/resume <name>` jumps straight to it. A miss offers a clicky "create it"
  affordance plus up to five fuzzy-matched suggestions to resume instead.
- **`/rename`** — rename the current conversation from the chatbox.
- **`sync` targets specific vids** — `sync vid|vids|video|videos #id[,#id…]`
  syncs exactly those videos (ids win); bare `sync vids` obeys the shift+tab
  channel scope (mirroring `analyze`).
- **`show` replies route by card** — replying to a `:system` card runs `sync`
  for that entity; replying to an `:enhanced` glance runs `analyze` — for vids,
  games, and channels alike.
- **`analyze` as a reply everywhere** — reply `analyze` to a `list vids` /
  `list games` / `list channels` to analyze that whole listed scope, or to a
  `show vid` / `show game` / `show channel` card to analyze that single entity
  (with `--help` + autosuggest coverage).
- **`list games upcoming` splits in two** — a `:system` card of games releasing
  within 30 days and an `:enhanced` card of the later/TBA ones; always both, each
  with its own subject-token intro (and an ironic empty-state line when a bucket
  is empty).
- **Mobile-tappable chatbox hints** — `shift+tab` / `shift+space` / `m` are
  clickable on touch (simulate the keypress) instead of being swallowed by the
  chatbox.
- **`show first|last`** selectors — `show last game`, `show first rpg game`,
  `show last published vid`, `show last vid` (= last published), etc. resolve to
  the earliest/latest entity (games by release date, vids by publish date) within
  the shift+tab channel scope.
- **Contextual command showcase** — when the chatbox is empty and idle, it cycles
  conversation-aware command suggestions (comet-revealed), regenerated after every
  turn from that turn's real entities (real `#ids`, always-valid forms). Rule-based,
  no Voyage; pauses on focus/typing, clears on input.
- **`/authenticate`** is now an alias for `/login`; while logged out, the slash
  suggestions surface only `/login`, and the other verbs explain that login is
  required.
- **`/notifications`** is now the canonical notifications command (the one shown
  in the slash palette); **`/notifs`** remains as an alias.
- **`/logout`** gains **`/exit`** and **`/quit`** aliases.
- **`list … with <cols> sort by <col>`** combine cleanly, with `sort` / `sorted`
  / `order` / `ordered` (and an optional `by`) all accepted.
- **Game platforms** — `platform set` / `platform unset` add and remove a game's
  platforms.
- **Paginated notifications panel** — loads 50 at a time and fetches more as you
  scroll (or press ↓ at the bottom), with a shimmering-dot loader and a playful
  "end of the list" marker (a new reusable copy dictionary). Replaces the old
  load-everything panel.
- **Async conversation deletion** — `dd` in the /resume sidebar hands the
  (potentially slow) cascade to a background job while the row shows a
  shimmering-dots placeholder; the state is persisted, so reopening the sidebar
  mid-delete still shows the dots.
- **Chatbox history recall** — oh-my-zsh-style prefix recall: type a prefix and
  walk previous matching commands.
- **Self-hosted DejaVu Sans Mono** — the terminal typeface (plus a braille face)
  is now bundled and subset, replacing Iosevka; source-misaligned ASCII art fixed.
- **`vid` category column** in `list vids`.
- **Scrollback jump pills** — a long conversation now shows small, centered
  navigation pills above and below the scrollback telling you how many messages
  are off-screen (`N messages above` / `below`, from a 50-variant copy
  dictionary), each with a clickable yellow **`ctrl+home`** / **`ctrl+end`** token
  that jumps to the start / end. The pills appear only when there's something to
  scroll to, hide while the sidebar or command palette is open, and reuse the
  exact off-screen-counting the `/share` page already used (extracted into a
  reusable, specced `Pito::Conversation::ScrollbackCount` service).

### Changed

- **Retention on channel and game** — the `:enhanced` retention chart is no longer
  video-only. It now renders for channels and games too, computed by views-weighting
  each of the scope's videos' retention curves (a channel is its videos; a game is
  its linked videos across channels).

- **`analyze` averages come straight from YouTube** — the average-view-duration and
  average-percentage-viewed charts (and the at-a-glance average-view-duration
  sparkline) now **pull YouTube's own per-day averages** and views-weight them across
  a multi-video scope, instead of deriving them from watch-minutes ÷ views or the
  retention curve. The numbers now match YouTube Studio exactly rather than drifting.

- **Chart cells are framed** — every analytics chart (at-a-glance and `analyze`,
  incl. the empty no-data canvas) now has a dashed border in the graph-paper dot
  color, so the two side-by-side 450px columns read as distinct despite the small gap.

- **`list games` drops the `release date` and `year` columns** — with releases now
  tracked per platform, a single sortable release/year column no longer makes sense.
  Both are gone from the `list games` table, the `with`/`without` column options, and
  their sort tokens (`list --help` updated). The `list released | upcoming | tba`
  status filter is unchanged.

- **Shimmer system overhaul** — one consistent set of shimmers, all sharing a single
  diagonal angle (135°) and speed (5s) as Tailwind tokens, all 20-step staggered:
  - **action** (pito-blue + purple) is now the *only* clickable shimmer — keys, table
    links, clickable tokens, `/resume` suggestions, `#id` links, shift+r.
  - **subject** and **reference** (decorative identifiers) read as normal foreground
    text with an orange→yellow sheen.
  - **network** activity (thinking block, IGDB search/import, notification "load more")
    shares one inverted shimmer (purple + pito-blue).
  - all **charts + score bar + time-to-beat** share one `--chart-shimmer` (pito-blue).
  - **`#reply` handles** and the **notification count** are now plain muted text (the
    reply action lives on shift+r; open notifications with ctrl+/).
  - achievement/shinies badges keep their per-tier colours but use the global speed/angle.
- **Context bar** — no longer shimmers. It keeps its green→red gradient and now counts
  only distinct backend messages (`:system`/`:enhanced`/`:confirmation` — follow-up
  re-renders don't add); each increment lights an **orange "lit-fuse" comet** that grows
  the fill from the old position to the new one, then settles.
- **`/themes`: click or tap to apply** — clicking (or tapping, on mobile) a theme in
  the themes sidebar now applies it immediately, the same as pressing Enter on it. The
  live preview stays desktop-only via the ↑/↓ keys.
- **Wider detail layout (450px columns)** — `show game` / `show channel` / `show vid`
  now use two **450px** columns (left media + right content), and the conversation
  column is sized to fit them exactly (964px on desktop). The banner / thumbnail /
  cover boxes render at their native 450px variant size (no more browser downscale).
  The `list`/recommendation **cover strips** and **channel matches** show the **top 5**
  (by score) on one row, with a tightened gap so they fit the narrower column.
- **Single-line chatbox** — the chatbox is shorter, with the textarea vertically
  centered; the `c to chat` hint (and the shift+tab / shift+space cyclers) now sit
  inline, right-aligned on the textarea's line, with symmetric left/right padding.
  The conversation name moved out of the chatbox to above the context bar (left of
  the `xx%`), shown only when the conversation is named.
- **Rake tasks drop the `tools` namespace** — every `pito:tools:*` task is now
  `pito:*` (e.g. `pito:totp`, `pito:clean`, `pito:games:*`, `pito:images:*`).
- **Normal text cursor in every input** — the chatbox, the ctrl+k command-palette
  search, the sidebar search boxes, and the conversation-rename field now use the
  browser's normal native caret. The bespoke JS caret/cursor machinery was already
  retired; the interim CSS block caret (`caret-shape: block`) is now removed too —
  one ordinary blinking caret everywhere.

- **`show game` channel matches show just the @handle** — each matched channel now
  shows its avatar, clickable **@handle**, and score bar, without the channel
  name/title line (the @handle identifies it). The `list channels` view still shows
  the title.

- **Inline chat suggestions removed; palettes stay** — the inline free-chat
  typeahead "ghost" (and the `tab` completion shortcut + its chatbox hint) is gone.
  Typing a natural-language message no longer ghost-completes verbs or arguments.
  The `/slash` command palette and the `#hashtag` reply-verb palette (arrow-key
  navigable, Enter to accept) are unchanged and remain the only suggestion
  surfaces. `tab` no longer completes anything (it still stays inside the chatbox
  rather than moving focus).
- **shift+tab / shift+space are contextual now** — the channel cycler (shift+tab)
  shows only while you're typing `list vids`/`list games`, and the period cycler
  (shift+space) only while typing `analyze`; otherwise the row shows `c to chat`
  (when unfocused) or nothing. The keystrokes are live only when their
  hint is showing, and the channel/period are **sent only when their cycler is
  visible** — so no other verb picks up a stale channel or period (`list games`
  with `@all` = all games; with `@handle` = games having a vid on that channel;
  `list vids @handle` = that channel's vids). The meta row is a single row on
  desktop and mobile with the middot separators removed.
- **`c to chat` hint** — the chatbox focus shortcut is **`c`** (yellow, clickable)
  and the caption reads **`c to chat`** (new `Pito::Copy` caption, replacing the old
  `chat` label) and shows on the **start screen, 404, `/chat`, and `/share`**. The
  meta line is a **single row on desktop and mobile** again (no more stacking). On
  `/chat` it still swaps with the shift+tab/shift+space cyclers by focus; the other
  surfaces show it always.
- **Native block caret replaces the custom JS cursor** — the bespoke
  caret/comet-trail JavaScript (mirror-based pixel math, ghost trail, showcase
  comet) is gone everywhere — the chatbox textarea **and every search/rename input,
  including the ctrl+k command palette and the sidebar IGDB search**; the browser's
  native caret is styled as a phasing block via CSS (`caret-shape: block`). Idle
  conversation hints now rotate through the input's `placeholder` every ~10s. This
  removes a class of caret bugs (the caret dropping 1–2px on hover, sitting under
  the placeholder on reload, and the broken caret on the `/share` page).
- **Analyze `:enhanced` is always lifetime** — the enhanced analyze card no longer
  follows the shift+space period (its audience-composition bars + retention are
  all lifetime anyway), so it shows the all-time picture and its intro copy says so
  (a dedicated 50-variant lifetime dictionary). The `:system` card keeps the
  shift+space period. (Sets up a 1-day-TTL cache for the enhanced card in 0.9.0.)
- **Notification badge** in the mini-status is a compact cyan-shimmer **`N*`**
  (was `N notifs`) and is **clickable** — click it (or `ctrl+/`) to toggle the
  notifications sidebar. The /resume sidebar shortcut labels are trimmed to
  `n rename` / `dd delete`.
- **`/config` credentials** dual-route to the right provider and mask secrets at
  the source.
- **Slash palette** triggers argument completion on a trailing space and sends on
  Enter at the verb stage.
- **`list channels`** is ordered by most-recently-published vid.
- **No more entity guessing in free chat** — `show`, `rm`/`delete`, and `list` no
  longer silently assume "game" when the second word isn't a recognised entity. In
  free chat the second token *is* the entity: a bare id (`show 123`, `rm 5`), a
  bare verb (`show`, `rm`), or an unknown word (`show foo`, `list foobar`) now gets
  a clear "I don't get it" nudge instead of a surprise game lookup. Explicit nouns
  (`show game 12`, `rm vid 5`, `list vids`) and `list`'s filter shortcuts
  (`list rpg`, `list upcoming`) are unchanged; reply (`#<handle>`) flows keep their
  context. `analyze` already worked this way (it suggests options).
- **Mini-status shows the build** — the nickname now carries a muted suffix:
  `gmrdad82@<tag>` on a Docker production image, `gmrdad82@localhost` (or your
  configured host) in development.
- **Analytics widgets own their reveal** — charts/bars animate with their own
  choreography (the Views bottom-up wipe, the score/TTB `=` left→right comet
  wipe); they always play. Message prose renders instantly (see Removed).
- **Mobile chatbox meta line** stacks each shortcut chip key-over-caption (2 rows
  per pair) with an ellipsised conversation name, instead of overflowing.
- **PITO logo broken-neon reveal** — on the start screen and the 404 page the
  block-logo flickers in glyph-by-glyph at random, like a faulty neon sign warming
  up, then settles (with the odd rare flicker). Its own animation, always plays.

### Removed

- **Message & theme-change reveal animations** — the per-glyph text reveals
  (typewriter, scramble, and the word-jump comet), plus the theme-change diff
  morph, are gone. Chat messages and theme switches now render **instantly**. The
  widget/chrome reveals stay and always play: chart sweeps (area/bar/metric),
  the context-bar dynamite fuse, the PITO logo flicker, the desktop sidebar
  slide, and shimmers — none of them respect the OS "reduce motion" setting any
  more, they always animate.
- **`/config motion` and `/config fx`** — with the content reveals gone, the
  animation on/off toggle and the reveal-style picker no longer have anything to
  configure. Both commands (and their `--help`, autosuggest, grammar, and the
  stored `fx_enabled` / `fx_effect` settings) are removed; the stored rows are
  deleted by a migration. **`/config sound` is unchanged.**

### Changed

- **Detail cards show Stats and Shinies as aligned rows** — on `show channel` /
  `show vid` / `show game`, the Stats line (`365 Views · 17👍 · 2💬`) and the Shinies
  badges are now key/value rows (label on the left, value on the right) instead of
  stacked headings; the Shinies badges wrap freely in their column.

- **Analytics chart columns keep a clean gap** — the at-a-glance, `analyze`, and
  per-game channel-distribution chart panels now each fill exactly one 450px column,
  so the two columns no longer touch or overlap. The channel recommendation column
  stays panel-free.

- **Share pages are simpler and unfold with one key** — a public `/share/:uuid` page
  is now a minimal read-only view: no auth mini-status, no scroll-nav, no command
  palette. The reduced chatbox is prefilled with **unfold**; press **`c`** to focus
  it, then **Enter** opens the full conversation (the hint swaps "c to chat" →
  "Enter to unfold", and the Enter affordance is a real link so it works without JS).
  Shared messages also no longer show their reply `#hashtag` (they're read-only).

- **Charts sit on a surface panel, not a dashed frame** — the at-a-glance and
  `analyze` metric cells now lift onto a surface background (chart + caption
  together) instead of the dashed border.

- **Copy affordance shimmers in the action colour** — the copy icon (share link +
  footage snippet) now uses the shared copy widget with the pito-blue↔purple action
  shimmer instead of a flat cyan, via one core component so both stay in sync.

- **Replies no longer elevate a message's background** — the "this was just changed
  by your reply" surface lift (`payload[:surface]`) was removed. A message keeps the
  background it was rendered with; follow-up replies don't re-tint the original.

### Fixed

- **Footage snippet command is readable again** — the `footage` command block was
  being shrunk to ~40% (an ASCII-fit scale meant for wide art) and gained a
  horizontal scrollbar. It now renders full-size and wraps to fit, readable on
  mobile too.

- **Thinking ASCII + scroll-nav polish** — the resolved thinking face (`( •_•)>⌐■-■`)
  now uses the same dim colour as its "…for 1.06s" text; the bottom scroll-nav pill
  drops its bottom border to match the top pill.

- **Unresolved messages can't be shared** — the `share` reply is now offered (and
  accepted) only once a message has finished loading (its thinking indicator
  resolved). Sharing an in-flight message (e.g. an `analyze` card mid-render) is
  refused with a clear message, and the reply menu hides `share` until it's ready.

- **Chart health colour is consistent across metrics** — on a small channel, the
  Watched-hours and Subs area charts rendered green from the baseline up (while
  Views, avg-view-duration and avg-%-viewed showed the expected red baseline). Their
  daily targets are fractional (< 1), and the plot's `1.0` y-scale floor was dragging
  the green anchor down to the baseline. The gradient anchor now uses the target's
  own scale, so an empty/under-target chart reads red at the baseline for every metric.

- **`analyze` subscribers no longer read zero** — the daily analytics query wasn't
  requesting subscriber gains/losses, so the subs chart and net-subs total could
  read 0; the daily query now pulls them and the subs numbers are correct.

- **Game likes show one heart, not two** — the `analyze` likes for a game showed both
  a vids heart and a channel heart. A game spans channels, so the channel heart was
  meaningless; a game now shows a single heart from its linked videos. (Channel shows
  one channel heart; a video still shows two — its own plus its channel's.)

- **Conversation scrollbar is clearly visible** — the scrollback's edge-fade
  gradient was masking the scrollbar itself; the fade was removed from the
  conversation scrollback so the slim themed scrollbar is fully visible.

- **`footage snippet` command is readable** — the copyable shell one-liner was
  rendering at the tiny browser "monospace" default; it's now pinned to the 14px
  base, with a copy icon replacing the "Copy" text.

- **Release countdown no longer fires a month early** — a game with a concrete
  date on one platform and a quarter (e.g. "Q3") on another used to store the
  quarter's *start* as its release date, so the countdown could announce "in 0 days"
  weeks before the real launch. Countdowns now come from the per-platform dates and
  only fire for **day-precision** releases — never counting down to a quarter or a
  year.

- **Analytics grids are always two columns** — the `analyze` message and every
  at-a-glance grid (show vid / game / channel) now lay out as a fixed 2×450px grid on
  desktop (stacked on mobile), so the braille charts sit side by side instead of
  collapsing to a single full-width stack. Every glance metric (including net subs at
  +0/-0) now carries a sparkline with a baseline floor, and a pending metric's loading
  comet rides in the caption row rather than floating over the chart canvas.
- **Less shimmer, more signal** — only actionable, thinking, network, and subject text
  shimmers now. Channel `@handles`, video/game `#ids`, scope chips, and table column
  headings are plain text; the subject shimmer is a single orange band and the (now
  reserved) reference shimmer a single yellow band.
- **Footage value never hides behind a bracket** — on the time-to-beat bar the inline
  footage value is offset past its tick (left or right of the pillar by where it sits),
  so a `0h` value at the far-left no longer overlaps the `[`.
- **Channel recommendation rows line up** — in `show game` the right-column avatars now
  match the left column's bars row-for-row: each tiny avatar is a 1px-ringed circle
  sized to one bar's height (its `:xs` variant regenerated to match).
- **Context bar meets the chatbox** — the conversation context meter now sits flush
  against the chatbox with no gap.
- **Chatbox lines up with the messages** — the chatbox / slash palette left border now
  aligns with the scrollback messages' left border on desktop (a residual column
  padding had pushed it 5px to the right).
- **Scroll-nav pills are created/removed, not shown/hidden** — the top/bottom "N more
  above/below" pills are now added to and removed from the DOM as you scroll (a stale
  `hidden`-class rule could never actually hide them, so the bottom pill lingered at the
  very bottom). They read correctly too: right singular/plural noun and verb ("1 more
  message remains", "3 more messages remain"), both pills gone at the extremes and on a
  short all-visible conversation, and the bottom pill sits flush against the context bar.
- **Scroll-nav pills breathe** — a little more horizontal padding on both pills.
- **Chatbox padding is tighter and even** — less left/right padding, and the gap from the
  left edge to the text now matches the gap on the right (the accent bar + gap had made
  the left side wider).
- **Cleaner game-import messages** — importing a game now shows a single thinking block
  (leftover ones from a previous version's extra messages are gone). The status message
  reads *"<game> is importing…"* (present tense, no `#id`) with the timestamp on the same
  row as the copy; the done message also puts its timestamp inline, its `#id` is now
  **clickable** (opens the game via `show game #id`), and the redundant "Type `show game`
  to see it in full" line was removed.
- **Anniversary / GOTY editions are importable** — IGDB tags some standalone releases
  (e.g. *Rayman: 30th Anniversary Edition*) as "bundles", which the game search filtered
  out. Bundle rows whose name says **GOTY / Game of the Year / Anniversary** now pass the
  filter alongside true combo bundles, so you can import them.
- **Footage value is readable on the time-to-beat bar** — the generic footage tick
  color was bleeding onto the inline value chip (fg-on-fg = invisible); the chip now
  keeps its inverted, legible colors.
- **Score value sits tight to the pillar** — the inline score-bar value chip is
  nudged 2px toward its marker.
- **No gap above the score bar** — removed a stale top margin (left over from when the
  score floated above the bar) in `show game` and the similar-games cards.
- **Conversation autocomplete** — the `:conversations` slot (used by reply/resume
  completion) resolves again; a new `Pito::Conversation` namespace had shadowed the
  top-level `::Conversation` model in the grammar resolver.
- **Channel banner refreshes on `sync channels`** — the banner (and avatar) were
  only fetched on OAuth connect, so a synced-but-not-reconnected channel never got
  one. Sync now refreshes both, digest-gated (no work when the image is unchanged).
- **Conversation column is centered on desktop** — the scrollback + chatbox now sit
  in a fixed-width, centered column (sized to fit a 6-cover message row) on wider
  screens; mobile stays full-width.
- **Score bar reads at the extremes** — the marker no longer clips off the track at
  0 or 100 (its position is clamped to 1–99 while the shown number stays the real
  score), and the score value now sits inline on the bar beside the marker (left for
  low scores, right for high) instead of floating above with a ▼.
- **Footage shows on the time-to-beat bar** — the footage value renders inline on
  the bar (**`0h`** when there's none — footage is never shown as a dash).
- **Resolved thinking blocks get a glyph** — a small random ASCII flourish marks a
  finished "thought for …" where the spinner was.
- **Fainter chart paper for hearts & bars** — the dotted background grid behind the
  heart and bar charts is lighter so the data stands out.
- **Full bars no longer overflow** — a 100% horizontal bar leaves a cell of
  headroom instead of spilling past the chart edge.
- **Readable chart axis labels** — Y-tick value chips paint over the braille in the
  message's own background colour with a hair of padding.
- **Tiny values still show on sparklines** — any non-zero point now renders at least
  the smallest braille bump instead of reading as a flat line.
- **Channel card polish** — the 'Avatar' label is vertically centered to the avatar,
  and the @handle is a clickable token that runs `show channel @handle` on click
  (same affordance as the #id tokens in show vid/game).
- **Visible conversation scrollbar** — the scrollback shows a thin, theme-colored
  scrollbar instead of hiding it.

- **Shiny badges fit three-up on mobile** — the compact achievement badges on the
  `show channel` / `show vid` / `show game` cards were locked to an 11rem min-width
  (only two fit per row). The compact form now has a **fixed slim width** and
  **truncates** (ellipsis) when a face is too long, so **three fit per row on
  mobile**. The shinies-command badges (the extended form, with dates) are
  unchanged.
- **`share` links use the host you're actually on** — the minted `/share/:uuid`
  URL now uses the request origin (scheme + host + port, e.g.
  `https://dev.pitomd.com`) instead of the static configured host (which read as
  `http://localhost:3027` behind a tunnel). Threaded from the request through the
  async dispatch job.
- **Bare `show channel` reads as a channel, not a game** — `show channel` with no
  `@handle` (and no channel scope) now asks *which channel* instead of falling
  through to the game picker; with a shift+tab channel scope set, it shows that
  channel directly.
- **`share` is hidden on confirmation prompts** — the reply menu on an ephemeral
  confirm/cancel message (e.g. a delete confirmation) no longer offers
  `share`/`revoke`/`unshare`; sharing a throwaway prompt made no sense.
- **Owner-set game platforms survive an IGDB re-sync** (no longer overwritten).
- **`/connect`** no longer shows a no-handle confirmation when already connected.
- **Channel avatar filenames are channel-unique** so the CDN can't serve a stale
  cached image across channels.
- **Follow-up parity** — delete/publish aliases, implicit `price <id> <amount>`,
  footage reply parity, and repliable publish/unlist/schedule on a video card,
  with the schedule id-less reply bug fixed.
- **Chat-verb suggestions no longer crash** on a bare complete verb — typing
  `list` / `ls` (or any verb) used to raise "negative array size" and drop the
  suggestion; fixed.
- **Targeted sync copy** — syncing a specific vid now reads `Sync #25?` /
  `Syncing #25 from YouTube…` instead of the misleading `#25 vids`.
- **Clearing the chatbox now persists** — emptying a saved draft (backspace to
  blank) is saved to the conversation, so a cleared chatbox no longer reappears
  with stale text after a refresh.

### Reliability

- **Exhaustive dispatcher-recognition specs** — a fast, DB-free spec net asserts
  the system's understanding of every verb × every keyword combination (with and
  without args, plus unknown inputs) across the slash, hashtag, and chat stacks.

## [0.8.0] — 2026-06-26

The **analtics** release — a chat-first `analyze` verb over the YouTube Analytics
API: per-video primitives cached (completed periods frozen forever), aggregated
across any scope, and rendered as metrics you refine with `with` / `without`.

### Added

- **`analyze` verb** (synonyms `analytics`, `stats`) — both as a chat verb
  (man-style `--help` + autosuggest) and via a `#<handle>` reply. Targets
  channels, vids, or games (id lists + synonyms accepted); scope resolves from the
  shift+tab channel filter and runs over the shift+space period. Each run fans out
  into atomic per-video / per-channel requests.
- **Analytics primitives store + completed-period freeze.** Per-video raw reports
  are cached in Postgres keyed by `(subject, report, date-range)` —
  entity-agnostic, so a video fetched for one scope warms every later scope that
  shares it (a channel analysis warms a later game analysis, no extra YouTube
  calls). A period whose end-date is ≥ 7 days past is **frozen permanently**
  (YouTube finalizes metrics in ~2–3 days); live periods carry a 1h TTL.
- **Two messages per analyze — `:system` + `:enhanced`** — each its own 50-variant
  copy dictionary. Every ordered metric renders as a "data-pulled" scaffold cell
  through one generic component (bespoke per-metric components come in a later
  pass). The per-message thinking indicator spans the message's full fan-out.
- **Refine with `with` / `without`.** Chat `analyze … with X,Y` / `without X,Y`
  whitelists or excludes metrics; replying `with` / `without` to an analyze message
  **mutates it in place** (re-rendered from the persisted scaffold, no re-fetch),
  while replying to a `show vid` / `show game` analytics glance emits a fresh
  analyze pair.
- **`show vid` / `show game` analytics glance is repliable** and now renders
  through the shared analytics component, with a witty nudge toward `analyze`.
- **ASCII art fits narrow screens.** A scale-to-fit controller uniformly shrinks
  the start-screen logo and in-message art (e.g. `/connect`) to fit mobile widths
  — alignment preserved, still live themed text — with desktop untouched.
- **`link` accepts multiple vids in one chat command** (`link game 1 with vid
15,14`), matching the reply path.

### Changed

- **"Comms" → "Comments" everywhere user-facing**, pluralized (1 comment / N
  comments). `comms` is still accepted as an input alias (with/without + columns).
- **IGDB import sidebar** renders at the single 14px base size (no font-size drift).

### Fixed

- **Shinies pluralize at a count of 1** — "1 Like" / "1 Sub" / "1 View" /
  "1 Comment", not "1 Likes" — across every metric.
- **Compact counts round down, never up** (`2,259` → `2.2K`), so a displayed count
  never overstates the real number.
- **A new `:system` / `:confirmation` message retires all prior live `#<handle>`
  replies** uniformly — typed verbs and replies-that-append alike — so stale reply
  affordances don't linger. Repeatable verbs (link/unlink) and in-place mutations
  are exempt.

## [0.7.6] — 2026-06-25

The **golden tape** release — the README now _moves_, and game prices read as coins.

### Added

- **CLI casts in the README** (recorded with [VHS](https://github.com/charmbracelet/vhs),
  themed in PITO's own synthwave palette):
  - **Operating PITO** — `pito --help` → `version` → `logs` → `rake` → `backup`, live.
  - **Install** — `curl | sh` showing the version picker → fetch (the "one line" proof).
  - **`pito update`** — the interactive stable/edge version picker switching the stack.
- **`Pito::Coin` — price as coin tiers.** Game prices now read at a glance as
  spinning gold coins instead of a bare `€`: 1 coin (≤ €9.99, budget) up to 5
  (> €79.99, premium/collector), thresholds at `9.99 / 29.99 / 59.99 / 79.99`.
  Price has three meanings: **unset** (`nil`) renders `—`, an **explicit 0** renders
  a Mario-style **star** + `0.00` (deliberately free — "genuine value", its own state,
  settable via `price set <id> 0`), and **> 0** renders the coins + the number
  (`🪙🪙🪙 59.99`). `Pito::Coin` owns the tier; `Pito::Formatter::Price` owns the number
  and the nil-vs-0 distinction (`unpriced?` / `free?`); `Pito::Game::PriceGlyphs`
  renders. Shows in the game list Price column, the game detail card (`:system`), and
  the linked-game card (`show vid` `:enhanced`).
- **`price` verb in `shift+r` replies.** Reply to a `list games` message with
  `#<handle> price set <id> <amount>` (or `price set <id> 0` for free) — previously
  only `show game` replies could set price.
- **Linked games in `list vids with games`.** The Game column now shows
  `#<id> <title>`, with `#<id>` a clickable cyan shimmer token (like the vid `#` id)
  that opens `show game #<id>`.

### Fixed

- **A not-found reply no longer consumes the `#<handle>`.** Replying to a
  `list games` / `list vids` / a `show game` linked-vids `:enhanced` list with a bad
  id (`#<handle> show 999`) returned the friendly "Don't have 999." but silently
  consumed the source's reply handle, so you couldn't retry without repeating the
  whole command. The not-found now keeps the list repliable (`Chat::Result::Ok` gained
  a `consume:` flag, set `false` for not-founds and forwarded by `ChatResultAdapter`).

## [0.7.5] — 2026-06-24

The **papercuts** release — chat/slash autosuggest + reply-shortcut fixes.

### Fixed

- **`/config` now submits cleanly.** The slash palette kept offering credential
  keys even while you typed a value or after you'd supplied them all, so Enter
  re-selected a key instead of sending. It now suggests nothing while you type a
  value and excludes keys already set — once they're all in, the palette closes and
  Enter submits. (No more dummy token to dismiss it.)
- **`sync` autosuggest.** Typing `sync channels ` now ghost-suggests `with`, then
  `with ` suggests `vids` — matching how `list … with` already completes.
- **`shift+r` (reply) works without focusing the chatbox first.** It's a global
  shortcut again: when the box isn't focused (and you're not typing in another
  field), `shift+r` focuses it and starts the reply.
- **`import` help is no longer truncated.** The hint read `import game <title>`, and
  `<title>` was parsed as an HTML tag — eating the rest of the line. Now `[title]`.

## [0.7.4] — 2026-06-24

The **safety-net & self-service** release: hands-off restorable backups, version
channels you pick at install/update time, and `pito` as a real PATH command.

### Added

- **Version channels (stable / edge).** Install and `pito update` are now
  interactive — pick a **stable** release (image tag _and_ CLI/scripts pinned to the
  same `vX.Y.Z` git tag, fully reproducible) or **edge** (`:latest` image + CLI from
  `main`). Available releases are listed live from the GitHub API. Non-interactive
  flags: `--version vX.Y.Z` / `--edge`. `.env` records `PITO_TAG` + `PITO_REF`.
- **`pito --version`** — shows the running version + channel (e.g.
  `pito 0.7.3 (stable)`), read from the image's OCI labels + `.env`.
- **Scheduled backups.** `pito backup-schedule` installs a daily systemd timer
  (`pito-backup.timer`, 03:00) that runs `pito backup` and self-prunes to the
  newest **7** — rolling, hands-off backups on the host. Also offered during
  install. Retention + location tune via `PITO_BACKUP_KEEP` / `PITO_BACKUP_DIR`.
- **`pito restore <dir>`** — restore a backup over the live stack (DB + assets),
  with a confirmation prompt (it's destructive) and a service restart after.
- **`pito backup --list`** — list existing backups with their artifact sizes.
- **`pito` on your `PATH`.** The installer now symlinks the CLI to
  `/usr/local/bin/pito`, so it runs as a bare `pito` from anywhere (the CLI
  resolves the symlink back to its install dir). `pito link` / `--link-only`
  (re)adds it, `pito update` keeps it current; `./pito` from the install dir
  still works if the symlink step is skipped.

### Changed

- **`pito backup` now prunes** to the newest `PITO_BACKUP_KEEP` (default 7) after
  each run, and honors `PITO_BACKUP_DIR`. The asset archive already captured
  rendered variants (same disk root); that's now documented.
- **README tour thumbnail** — the hero now uses the real "Inception Wednesday"
  tour-video thumbnail, pre-sized to its display width (no browser downscaling).

## [0.7.3] — 2026-06-24

The **less-is-more** release. The published image goes on a serious diet —
**870 MB → 365 MB (−58 %)** — without giving up a single feature, backups move out
of the container onto the host where they actually survive, and the installer
finally finishes the job (services enabled, tunnel running) on its own.

### Added

- **`pito backup`** — a host-side, durable backup. Writes `./backups/<timestamp>/`
  on the host: `database.sql.gz` (via `pg_dump` run inside the Postgres container —
  version-matched, pgvector embeddings included) and `active_storage.tar.gz` (your
  avatars/thumbnails/covers). Restore is a documented one-liner. Replaces the old
  in-container task, which quietly wrote backups _inside_ the ephemeral web
  container — i.e. straight into the void on the next recreate.
- **Hands-off self-host.** The installer now **enables + starts** the `pito` systemd
  service itself (no more "here's the command to run"), and **configures + runs
  cloudflared as a service** — tunnel config lands in `~/.cloudflared/config.yml`,
  an existing tunnel is reused, and the tunnel comes up on boot with no manual
  `cloudflared tunnel run`. Re-running the installer is idempotent: it keeps your
  master key, Postgres volume (channels/videos/games/`/config` keys), and TOTP.
  `pito update` is systemd-aware too — it pulls, restarts via the service (`sudo
systemctl restart pito`) so the unit stays the owner, and prunes the old image.
- **Dev tabs are unmistakable.** In development the favicon turns **red** and a
  full-width **DEVELOPMENT** banner pins to the bottom (label from `Pito::Copy`), so
  a dev tab is never confused for production.

### Changed

- **Image rebuilt on Alpine/musl: 870 MB → 365 MB.** `ruby:3.4-alpine`; the runtime
  stage carries only shared libraries (`vips`, `libpq`); the build toolchain and
  `-dev` headers live in the discarded build stage. Native gems (nokogiri, pg, ffi,
  ruby-vips) and Thruster run on musl; the POSIX-sh entrypoint replaces the bash one.

### Removed

- **From the runtime image:** the build-only **Tailwind CLI** (~114 MB; CSS is
  precompiled at build time), the shipped **bootsnap cache** (rebuilt lazily — first
  boot is a touch slower, the only tradeoff), gem documentation, **`postgresql-client`**
  (backup is host-side now), **`curl`**, the C toolchain, and **bash/zsh** (busybox
  `sh` is the shell).
- **In-container backup** — `Pito::Tools::Backup` + the `pito:tools:backup` rake task,
  superseded by `pito backup`.

### Fixed

- **The DEVELOPMENT banner reaches both edges** — dropped a dead `scrollbar-gutter:
stable` that reserved a permanent ~6 px strip down the right of every page (the
  window never scrolls; only the inner scrollback does).

## [0.7.2] — 2026-06-24

The **polish, prose & paper-cuts** release. PITO gets its proper name (uppercase,
at last), a README that actually moves, a guide for extending it — and a fistful of
fixes for the ways it used to quietly eat your message or refuse to install.

### Added

- **`docs/extending.md`** — concrete, code-grounded guides for the four common
  extensions: a new **theme**, a new **language**, a new **message-content type**,
  and a new reveal **fx**. Dual-audience (human contributors and AI agents alike).
- **README revamp** — the origin story (the name is a Spanish nursery rhyme), the
  "why it exists" pitch, **animated GIFs** of the chat / linkage / scheduling /
  themes, a **collapsible 19-theme gallery**, and a Sponsor section. Install docs gain
  the `--host` / `--dir .` flags for a non-interactive, in-place install.

### Changed

- **pito → PITO.** The product name is now written PITO in all prose and user-facing
  copy. Code identifiers stay lowercase — the `Pito::` namespace, the `pito` CLI,
  `bin/pito`, `pito.copy.*` i18n keys, URLs, and paths are unchanged.
- **Leaner image.** `.dockerignore` now excludes `node_modules`, `docs/` (incl. the
  ~14 MB media gallery), `spec/`, and the dev `public/pito-storage` blobs — roughly
  60 MB off a local build, ~17 MB off the published image.

### Fixed

- **The chatbox no longer eats your message.** Removing the `/up` route in 0.7.0 left
  the cable-health monitor pinging a now-404 endpoint, so ~60 s into every session it
  falsely flagged the WebSocket "offline" — after which hitting Enter reloaded the
  page (restoring a previous view) instead of sending. The brittle HTTP poll is gone;
  submission always POSTs over HTTP regardless of cable state.
- **The Docker install actually installs.** Two fresh-install crashes fixed: an unset
  `RAILS_MASTER_KEY` was injected as a blank string and corrupted credential
  generation (dropped from compose — the mounted master key is the source of truth);
  and the compose `:ro` mount auto-created `config/credentials.yml.enc` as a
  read-only **directory** before it existed, crashing the generator (bootstrap now
  uses a plain `docker run`).
- **Shinies messages are no longer falsely repliable** — they carried a `#handle`
  reply target nothing consumed; the dead handle (and its `shift+r` affordance) is
  gone.

## [0.7.1] — 2026-06-23

The **polish** release on top of 0.7.0: PITO now keeps your pictures, talks back
when you say hello, ships its arm64 image without the emulation tax, and stops
pinging Slack five times for one green push.

### Fixed

- **Active Storage blobs now persist.** The production image runs as a non-root
  user, but the Active Storage `:local` root (`/var/lib/pito-assets`, backed by
  the persistent `rails_storage` volume) was never created in the image — so a
  freshly-attached Docker volume came up root-owned and the first avatar / cover
  art / video thumbnail upload (and its vips variants) failed with `EACCES`. The
  `Dockerfile` now creates that directory owned by the runtime user **before**
  dropping privileges, so the volume is seeded writable and your media survives
  container recreate, rebuild, and `docker compose pull`. (Postgres data already
  persisted via its own volume.)

### Added

- **Greetings & farewells.** `hi` / `hello` / `hola` / `hey` / `yo` / `good
morning` … and `bye` / `goodbye` / `hasta luego` / `ciao` / `later` … now get a
  witty reply (one of 50 variants each) instead of an error — matched as
  whole-input phrases in the chat parser, isolated from the verb grammar.
- **Witty fallback for nonsense.** Input PITO genuinely can't parse ("boo!", "I'm
  hungry") no longer errors; it returns a `:system` reply from 50 variants, always
  nudging toward `help`. Errors are now reserved for _recognised_ verbs with bad
  arguments.

### Changed

- **Release builds arm64 on a native runner.** Multi-arch publishing moved off
  QEMU emulation onto native per-arch runners (`ubuntu-24.04` for amd64,
  `ubuntu-24.04-arm` for arm64) with a digest-merge step — far faster, same
  `linux/amd64 + linux/arm64` result, so Apple Silicon / Raspberry Pi self-hosters
  keep a native image.
- **Slack CI notifications de-spammed + randomized.** One push used to fire ~5
  green pings (CI ×2 + JS + Docs + Release). Now exactly one green "heartbeat"
  (the CI `rails` job); every other workflow notifies only on failure. The
  Deadpan Butler also picks from a pool of lines so it stops repeating itself.

## [0.7.0] — 2026-06-23

The **local-first self-host** release. PITO stops being "clone the repo and pray"
and becomes "one command, on your own machine." No cloud, no Kamal, no monthly
anything — your laptop, your data, still.

### Added

- **Docker self-host in one command.** `curl … script/install.sh | sh` lands a tiny
  `./pito` install (compose file + CLI), generates your _own_ secrets
  non-interactively (no editor, no host Ruby), pulls a **prebuilt multi-arch image**
  from `ghcr.io/gmrdad82/pito`, enrolls your TOTP login, and offers a Cloudflare
  tunnel + a systemd unit for reboot-persistence. No git clone.
- **`pito` operator CLI** — one self-contained script (no repo, no Ruby) for the
  Docker stack: `up`/`down`, `totp`, `console`, `logs`, `rake`, `clean`, `install`,
  `update`, `service`, `cloudflared`.
- **`/jobs` slash command** — your window into SolidQueue: `status` (workers, state
  counts, recent failures), `requeue <id|all>`, `run <key>` (run a recurring task
  now), `pause` / `resume`. Its subcommands autocomplete in the command palette.
- **Background jobs actually run in production** — the Docker stack runs the
  SolidQueue supervisor inside Puma (`SOLID_QUEUE_IN_PUMA`), so chat-triggered jobs
  and the recurring schedule (nightly sync, achievements, release countdowns) fire on
  a single self-host box without a separate worker process.
- **`pito:tools:clean`** — clears the `tmp/` scratch (keeping `tmp/storage`, `tmp/pids`,
  and `.keep`) and truncates dev `log/*.log`. Safe for blobs: dev Active Storage lives
  under `public/pito-storage`, not `tmp/`.
- **`PITO_APP_BASE_URL`** — set your public host once; it wires Host Authorization,
  URL helpers, and asset delivery. Pairs with a Cloudflare Tunnel for remote access.
- **Dev conveniences** — `PITO_DEV_JOBS=1 bin/dev` to run the recurring scheduler
  locally, and a development-only `/login 123456` dummy code (override with
  `PITO_DEV_TOTP_CODE`, disable with `…=off`) so you can sign in without an
  authenticator. Both are impossible outside development.
- **Release pipeline** — `.github/workflows/release.yml` builds + pushes the
  multi-arch image to GHCR on a **version-tag push only** (never per-commit); a new
  CI `scripts` job shellchecks every shell script.

### Changed

- **Explicit environments**: Docker runs **production**, native `bin/dev` runs
  **development** — documented end to end.
- **Recurring jobs are off under `bin/dev`** by default, so a dev box never quietly
  hits YouTube/Discord on a cron.
- **Leaner, tidier container**: production image drops test-group gems
  (`BUNDLE_WITHOUT="development test"`); compose caps container log growth via the
  json-file driver and mounts each owner's own secrets over the baked-in copies.
- **Fixed the stock `bin/` scripts**: `bin/setup` no longer waits on a phantom
  `redis` (and uses the right compose stack); `bin/test` works again (added the
  missing `bin/test-prepare`). `bin/boot` is now a thin shim forwarding to `pito`.
- **The `shift+r` reply hint now shows on every addressable message** (not just the
  most recent), so any message with a `#handle` is one click from a reply.
- Agent/working docs moved from `tmp/docs` to a gitignored `docs/claude/`.

### Fixed

- **Authenticated 404s no longer 500.** The not-found page rendered the start screen
  with `channels: nil`, blowing up `@channels.any?`; channels now coerce to `[]`.
  (Also explains the occasional dropped chat turn — a request that 500s never finishes.)
- **The game picker no longer hijacks the chatbox.** With a picker sidebar open, its
  keyboard nav stole Enter — injecting `show`/`rm game #id` over whatever you were
  typing. It now ignores keys while focus is in a field outside the picker.

### Removed

- **Kamal** (`config/deploy.yml`, `.kamal/`, `bin/kamal`) — PITO is local-only; there
  was never a cloud-deploy story to maintain.
- The stock **`/up` health route** — single-owner tool, not a load balancer.
- **Action Mailer, Action Mailbox, and Action Text** — all unused (notifications ride
  Slack/Discord webhooks).
- The **`jbuilder`** and **`bcrypt`** gems — neither was used.

## [0.6.0] — 2026-06-23

The **it-has-to-look-good** release. PITO grows a trophy cabinet (shinies),
learns to shimmer, trails a comet behind your cursor, and surfaces analytics at a
glance — because if you're going to stare at your numbers all day, they ought to
look good doing it.

### Added

- **Shinies** — lifetime achievements across **subs, subs gained, views, watch time, likes,
  and comms** (subs is channel-only; subs gained is per video/game), on a 22-step tier ladder
  (1 → 10M) color-coded by tier. Unlocked by a
  standalone 3×/day refresh; each unlock fires a **🏆 notification** (Slack /
  Discord + in-app), and the biggest shiny per metric shows on the video/game.
- **`shinies` command** — `shinies channel @handle` / `shinies video <id>` /
  `shinies game <id>` (also context-aware as a reply): a full per-metric breakdown —
  title, a full-width progress track, and the obtained shinies in order.
- **Footage** row on the `show game` card (before Price).
- **Stats counters under the cover** on `show game` (views / likes / comms, summed
  from linked videos), like `show video`.
- **Notification sound** — a short chime plays when a notification arrives
  (debounced for bursts; never on read/unread toggles; respects `/config sound off`).
- **`/notifications` renamed to `/notifs`** — opens the notifications panel (same as `ctrl+/`).
- **Analytics on `show video` & `show game`** — the enhanced card now shows a scalar
  table (views, watch hours, avg view duration, avg % viewed, subs gained/lost, likes,
  dislikes, comms) with **trend-coloured numbers** vs the prior period (green up / red
  down, neutral otherwise). For a game the figures are **summed across its linked
  videos**. The card appears instantly with a one-line intro and **fills in the
  background** — the "thinking…" spinner keeps cycling until the numbers land, so the
  page never blocks on YouTube, and a refresh mid-fetch is safe. The metrics lay out in
  uniform key/value columns that fill the card width and wrap aligned (every key shares one
  width, every value another, so a metric landing on the next row lines up with the row above).
- **Smarter `list` parsing** — `list` with no noun lists the **games** library, and filter terms
  are matched against a known vocabulary (genre aliases like `rpg`/`fps`, platform synonyms like
  `ps5`/`switch`, and `upcoming`); any token that isn't recognized vocabulary is treated as filler
  and **silently dropped** instead of rejected. So `list rpg ps5 please` lists games filtered to the
  **Role-playing** genre on **PlayStation 5**, ignoring `please` — no "didn't understand" error.
  When an unrecognized token (≥4 chars) is within two edits of a real genre/platform/`upcoming`/noun
  term, `list` offers that correction (`list rpgg` → _"Did you mean `rpg`?"_) instead of listing.
  Noun routing runs through one shared vocabulary: `games`/`game`/`gamez` → games,
  `channels`/`channel` → channels, `videos`/`video`/`vids`/`vid` → videos.
- **Message intros shimmer their subject** — the subject of an intro (the video / game title, or
  the `count` + noun in list intros like "11 games" / "6 channels") now carries a pito-blue→purple
  shimmer, and channel `@handle` references in intros shimmer cyan. Titles stay HTML-escaped.
- **Every message types out, each with its own thinking indicator** — response messages now
  reveal via the typewriter (including the detail / list / analytics / shinies HTML cards, not just
  plain text), and each message carries its **own** thinking indicator that resolves when _that_
  message is ready; a turn finishes only when all resolve, so a still-filling analytics card keeps
  its own spinner while the rest of the turn settles. Your typed command also **types itself back**
  as the echo, and the working-dots clear the moment that echo lands (not when the whole turn
  finishes). Under the hood, typed commands and `#handle` replies now run through one
  shared dispatch finalizer, so replies get identical canonical message kinds and honor the
  selected period / channel / viewport — exactly like typing the command.
- **Custom block cursor with a kitty-style trail** — the chatbox's block cursor now leaves a
  short, fast-fading trail as it moves (matching kitty's `cursor_trail`), and the same custom
  block cursor now appears on the single-line inputs too — game/video pickers, IGDB search,
  conversation rename, and the `ctrl+k` palette (made monospace to match). On a word-jump
  (`ctrl+arrow`, `Home`/`End`, or a far click) the trail draws a **continuous morphing comet** (3–5
  stretched segments that tile edge-to-edge, no gaps) — full height at both ends, pinching thin
  through the middle — that streaks from the old caret position to the new one and retracts toward
  the cursor. The caret and its trail are **pito-blue**. Respects
  `/config motion` + reduced-motion (solid block, no trail/blink when off).
- **`/config` autosuggest** — typing `/config ` shows a **browsable list** of providers, and
  `/config <provider> ` lists that provider's setting/credential key names (secrets masked) —
  navigate with ↑/↓ + Enter (the suggestion now layers _below_ the block cursor — above the
  type-fx and trail layers — fixing a case where the cursor was hidden while a suggestion showed).
- **Reveal effects** — pick how messages reveal with **`/config fx <typewriter|scramble|comet>`**
  (default typewriter): **typewriter** (now log-scaled, so long messages don't drag — a fast floor,
  capped ceiling), **scramble** (the whole line sits as random-glyph noise and decrypts left→right
  to the real text), or **comet** (a blurred light-sweep wipes across the line, revealing the text
  behind it as it passes). `/config fx --help` shows each one live, looping. Bars, avatars, covers,
  and thumbnails always pop in whole; respects `/config motion` + reduced-motion.
- **`dd` deletes a conversation** — in the conversations sidebar, pressing `d` twice (arm →
  confirm) deletes the highlighted conversation; a `dd` hint shows beside the rename hint.
- **Mobile swipe-to-delete** — on touch screens, swipe a conversation row left to reveal a red
  **delete** button (tap to confirm; no accidental full-swipe). Desktop keeps `dd`.
- **Searchable picker sidebars** — `show game` with no id now has a **search box** and shows
  **PS · Switch · Steam** icons beside each game; `show vid` with no id opens a matching picker
  with a search box and the channel **@handle** beside each video (it previously errored
  "Which game?"). Both load 50 rows and re-query the whole library as you type — with the
  same shimmering dots indicator the game-import search shows while a query is in flight;
  pick with ↑/↓ + Enter.

### Changed

- `show video` & `show game`: the key-value table moves up with **Title as its first
  row**; the **Description** moves below it.
- **`comments` → `comms`/`Comms`** everywhere user-facing (`comments` still accepted
  as an alias).
- **Mini-status bar:** "notification(s)" → **notif / notifs**; the auth label is now a
  configurable **nickname** (set with `/config me nickname=…`, default `gmrdad82`) when
  signed in, and **tarnished** when not.
- **Thinking indicator now cycles its verb** every 5s (`Executing…` → `Computing…` → …)
  instead of showing one fixed word, and the final `…ed for Ns` uses the verb that
  was on screen last. The 5s cadence is a single constant; the animation is
  refresh-safe (time-derived).
- **Stats counters reworked** into reusable components — `show video` / `show game` read
  `42 Views · 4👍 · 0💬` (full-word labels, with thumbs-up / message-square icons for likes &
  comments), `list channels` reads `Subs · Views` with `Vids` on its own row; both lead with a
  **Stats** heading and left-aligned Shinies. The separate stat **legend is gone** (self-explanatory).
  Icons are vendored **Lucide** outlines (no gem, ≤1em, theme-aware via `currentColor`).
- **`show game` order** — the recommendations card (channel suggestions + similar games)
  now comes **before** the analytics card, so the recommendations land first while the
  slower analytics fill in.
- **Keyboard-shortcut hints shimmer** — every yellow shortcut token has a slow diagonal
  yellow→orange shimmer, staggered per token so they don't pulse in unison.
- **Identifiers shimmer** — channel `@handles`, video/game `#ids`, and the `@all` /
  period (e.g. `28d`) scope chips now carry a slow diagonal **cyan→pito-blue** shimmer
  everywhere they appear (detail cards, list rows & sortable column headers, pickers,
  recommendations, the chatbox filter). Reply tokens (`#chi-4450`) get a distinct
  **blue→purple** shimmer so they read apart from `@handles`/`#ids`. All shimmer kinds
  share 20 staggered offsets so neighbouring tokens never pulse in sync, and all respect
  `prefers-reduced-motion`.
- **shift+r** reply (hashtag) picker now opens **inline above the chatbox** (was a
  centered modal).
- **Unified `--help`** — every command (`/config`, `/games`, slash + chat verbs) renders
  help in one man-page style.
- **Notifications panel** sorts unread-first then read (each newest-first), applied server-side
  when the panel opens (marking a row read/unread updates it in place without re-sorting — see
  _Notifications read-state_ below).
- **Analytics now follow the shift+space interval.** The glance figures on `show video` /
  `show game` are computed for whatever window you've selected (7d / 28d / 3m / 1y /
  lifetime), default **7d**, persisted per conversation — change it with shift+space and it
  sticks across reloads. The default lives on the conversation, not in the analytics layer.
- **Analytics table** — each metric is a label/value pair (label left, value right-aligned) that
  flows in a flex-wrap row, auto-filling as many columns as the width allows, in canonical order
  Views, Watched hours, Avg view duration, Avg viewed %, Subs, Likes, Comms. **Subs shows
  `+gained/-lost`** (green gained / red lost); **Likes is compacted to `N👍/N👎`** in a single
  cell (thumbs-up green / thumbs-down red — the standalone Dislikes row is gone); Comms is a
  plain count.
- **Trend numbers** (the green/red analytics figures) now shimmer in the same diagonal
  direction as the other shimmers, sharing the same 20 staggered offsets.
- **Reply tokens recoloured** — the `#chi-4450` reply handle shimmer is now **purple→blue**
  (it was blue→purple), keeping it visually distinct from the cyan `@handle` / `#id` shimmer.
- **Shimmer phases scatter properly** — neighbouring tokens (sequential `#ids`, similar
  `@handles`) no longer drift into near-sync; the offset is now a hashed (CRC32) bucket so
  close values land far apart in the 20-slot cycle.
- **Similar-games line** drops the middot — now just `#id Game Title` (shimmer id + a thin flex
  gap + title).
- **Shinies badges redesigned** — every badge now uses one uniform **rounded** border (was a
  per-metric ASCII box), with a soft highlight that **travels around the border edge**, and the
  unlock date is muted. (This also fixes badges rendering with a misaligned right edge on mobile.)
- **Shinies badges: two forms + full-word labels** — badges render as **compact** (value + word,
  e.g. `1K Subs`) or **extended** (value + word, with the muted unlock date on a second line),
  and use full-word labels (Subs / Views / Likes / Comms / Watched) instead of abbreviations.
- **Milestone track points at your next goal** — the reached portion of a shinies progress
  track now shimmers in the **colour of the next tier** you're climbing toward (blue heading to
  2K, cyan heading to 500, …), so the track shows momentum, not just history.
- **Score & time-to-beat bars shimmer** — a subtle pito-blue highlight sweeps across the
  gradient bars on the `show game` card.
- **`show game` cover pans** — the tall portrait cover now sits in a 16:9 box matching the video
  thumbnail and slowly drifts top↔bottom (Ken-Burns) to reveal the whole art; static and
  top-anchored when `/config fx` is off or reduced-motion is on.
- **Mobile-adaptive detail cards** — on narrow screens (< 768px) the `show video` /
  `show game` cards (and the linked-game card) stack into a single column — cover/thumbnail
  on top, the details table beneath — instead of being squeezed into two columns; desktop
  keeps the two-column layout. (PITO's first responsive breakpoint.)
- **Linked-game card upgraded** — when a video links a game, `show video`'s linked-game card now
  uses the same big Ken-Burns cover + two-column layout as `show game` (was a small static cover),
  stacking on mobile.
- **Mobile hairline divider** — on narrow screens (< 768px), a faded hairline now separates the
  cover/thumbnail column from the details table on the `show video` / `show game` / linked-game
  cards (hidden on desktop, where the two-column layout needs no divider).
- **Keyboard-shortcut hints are now tappable** — every shortcut hint (`Esc`, `shift+r`,
  `shift+tab`, `shift+space`, `ctrl+k`, `ctrl+/`, `m`, …) responds to a click/tap by firing
  the same action as the key, so the app is usable on touch/mobile. They also show a pointer
  cursor so the tap target is obvious; otherwise unchanged.
- **`Esc` hint is now a real keybinding** — the `Esc` shown on the command palette and the
  sidebars renders as the standard yellow shortcut (with the shimmer) and is tappable, like
  every other keyboard hint, instead of plain dim text.
- **Mobile sidebar overlay** — on narrow screens (< 768px) the sidebar (conversations,
  notifications, pickers, themes) opens as a **full-width overlay on top** of the
  conversation instead of squeezing it; desktop keeps the side-by-side panel. Still respects
  `/config fx` (snaps instead of animating when motion is off).
- **Command-palette commands are clickable** — clicking a `ctrl+k` palette row selects it and
  prefills the command into the chatbox (same as arrow-to-it + Enter — press Enter to run), and the
  command token (e.g. `/connect`) shimmers cyan.
- **Sidebar rows are clickable** — game/video pickers, `/resume` conversations, and IGDB
  import results activate on click, identical to highlighting + Enter.
- **Notifications read-state** — moving the cursor onto a notification marks it read; clicking
  toggles read/unread; the list no longer re-sorts live (it re-sorts only when the panel is
  re-opened, so rows don't jump). The `SPACE`-to-toggle binding is removed.
- **Shinies progress track** — the in-progress segment (your current standing → the next tier)
  now shimmers too, in the next tier's colour. The track also **collapses** to a compact
  windowed view — `1 … prev current next … 10M` — with a shimmering `─···─` ellipsis bridging
  the skipped tiers, so it reads cleanly (especially on mobile).
- **Click an `#id` to open it** — clicking a video/game `#id` anywhere in the scrollback
  (detail/recommendation cards, list rows, the linked-videos/linked-game cards) fills
  `show video #id` / `show game #id` and **runs it** (auto-submit). Clicking a reply `#handle`
  (or its `shift+r` hint) fills `#handle ` ready for a verb — prefill only, no submit.
- **Timestamp middot dropped everywhere** — message intros now read `HH:MM intro` (a single
  space, no `·`) across every message, not just the similar-games line.

### Fixed

- `list channels --help` now renders in the man-page format like the other list verbs.
- Clicking the `shift+tab` / `shift+space` hints now **cycles the channel / period in place**
  instead of yanking focus into the chatbox (the other tappable hints still focus, as before).
- The intro timestamp (`HH:MM`) now leads the copy on a single line across every
  detail and enhanced card (`show video` / `show game`, the linked-game card, analytics,
  shinies) — long copy wraps beneath it instead of the timestamp dropping to its own row.
- With the **ctrl+k palette open over a sidebar**, arrow/Enter keys now drive only the palette
  — the conversation list, notifications, the game/video pickers, and the IGDB import-results picker
  all bail while the palette is open (no more dual cursor).
- The notification chime no longer plays when you **toggle a notification read/unread** — it
  sounds only for a genuinely new notification (tracked by the latest notification id, not the
  unread count, which a toggle also moves).
- Sidebar lists (notifications, pickers, conversations) now scroll fully to the top — the
  first row is no longer clipped by the top fade gradient at max scroll.
- The sidebar no longer lingers on the **start screen / 404** — deleting your last
  conversation drops you to the start screen with the sidebar dismissed (it was being
  re-opened from `localStorage` right after the dismiss).
- **Analytics now actually appear** on `show video` / `show game` — the filled table was
  rendering without a replaceable DOM id, so the background job's live update never landed
  on the page (it sat on the intro). The card now updates in place the moment the data is ready.
- `list games` platform logos now reveal in step with their row (no longer pop in early).
- **Avatars, video thumbnails and game cover art no longer vanish** — local (dev)
  ActiveStorage moved out of `tmp/` (which gets wiped) into a gitignored `public/` folder
  that survives, and the image-repair sweep (`rake pito:images:fix`) now also re-attaches
  missing channel avatars (not just covers/thumbnails).
- **Replies now behave exactly like typed commands.** Triggering `show` (or any verb) from a
  `#handle` reply previously diverged from typing it: its analytics card stayed stuck on the
  placeholder and never filled, errors were swallowed silently, and no "thinking…" spinner
  showed. Replies now fill analytics, surface errors in the scrollback, and show the spinner —
  same as chat.
- **`show vid` linked-game card was missing its `#id` row** — added, with the shimmer id, to
  match the full game card.
- **Security:** list-mutation replies (`#handle add/remove/sort …`) now require an active
  session, like every other command (they were ungated).
- **Recommendation score bar** no longer touches the game title above it (added spacing).
- **Stats / Shinies headings** on the `show video` / `show game` cards render at normal weight
  (not bold), and their badges use the compact dateless form.
- **Removed the redundant "Scheduled" column** from `list videos` — it showed `—` for nearly
  every row. (The `list videos scheduled` filter still works.)
- **Removed the underline** on the `list channels` `@handle` link (it kept the cyan shimmer).
- **`schedule` and `slate` now autosuggest** — the `schedule` reply verb shows in the
  typeahead and `slate` (schedule to the next open slot) is offered for its argument, in both
  chat (`schedule <id> slate`) and replies (`#<handle> schedule slate`).
- **List-column reply verbs renamed `add`/`remove` → `with`/`without`** — matching the
  `list … with <col>` chat syntax (`#<handle> with views, likes` / `#<handle> without game`).
  The old `add`/`remove` are no longer accepted.
- **Lists default to newest-first** — `list channels`, `list videos`, and `list games` now
  sort by **ID descending** (biggest/newest first) by default instead of alphabetically; an
  explicit `sort by <col>` still overrides.
- **Reply typeahead shows every available verb** — typing `#<handle> ` now opens a palette of
  all the actions valid for that message (`with`, `without`, `shinies`, `schedule`, `show`,
  `link`, …), navigable with arrows/Tab, instead of only ever ghosting the first one (`show`).
  Fixes `with`/`without`/`shinies`/`schedule` being effectively invisible in replies.
- **Bar / track shimmers now stagger** — the score & time-to-beat bars and the shinies progress
  track had their per-element offset reset by an `animation` shorthand (defined after the offset
  classes), so they pulsed in unison; switched to animation longhands so the 20 staggered offsets
  apply.
- **Time-to-beat bar glyphs no longer vanish mid-shimmer** — the `=` fill stays painted at every
  frame (the highlight now rides over the glyphs instead of dropping the text clip).
- **Shinies badge ring & progress-track highlight** use a **per-tier contrasting accent** instead
  of white (white read poorly on the lighter tiers); theme-aware across all palettes.
- **Repeated list tokens no longer pulse in sync** — the shimmer offset is now seeded by row id,
  so the same `@handle` repeated down every row scatters across the 20 offsets.
- **Consumed list headers go quiet** — once a list message is consumed (historical scrollback),
  its sortable column headers render plain muted instead of shimmering and bold; live lists still
  shimmer.
- **Conversation rename shortcut** moved from `` ` `` to `n` (and `ctrl+`` ` ```→`ctrl+n`).
- **`/config fx` is now `/config motion`** for the on/off animation toggle — `/config fx` was
  repurposed to select the reveal effect (above).
- Analytics "Watch hours" label corrected to "Watched hours".
- Mobile sidebar no longer opens scrolled below the fold — the conversations header + list are
  anchored to the top on open (an in-place rename no longer yanks the list back to the top).

## [0.5.0] — 2026-06-20

The first tag. The actual headline: **it exists, and it mostly works.** One person
can run a fistful of YouTube channels from a single chatbox without renting a SaaS
subscription by the month — there are almost certainly a few bugs lurking in here,
but the core loop holds and the lights stay on.

Because it's the first release, this entry documents the **whole command language**
rather than a diff; future releases will only note what changed. Everything below
is typed into the one chatbox; replies use a `#<handle>` prefix the message itself
shows you.

### What works today

- Manage **many YouTube channels** from one chat-style terminal — mostly
  read-only; the only writes to YouTube are **publish / unlist / schedule / delete**.
- **Games** from IGDB with **similar-game** and **channel** recommendations
  (Voyage embeddings), explicit **video ↔ game linking**, a manual **footage**
  total, and a per-game **euro price**.
- **Slack & Discord** notifications (rich, colored, emoji'd) for reauth, sync
  summaries, and upcoming-release countdowns — with a live in-app unread badge.
- Full **keyboard navigation**, self-hosted via Docker, free.

### Command language — chat verbs

Each verb has a `--help` man page (`<verb> --help`).

| Verb                  | Forms                                                                   | What it does                                                                        |
| --------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `list`                | `list games \| list vids \| list channels`                              | List your library; games/vids take `with <columns>` and `sorted by <column> [desc]` |
| `show`                | `show game <id>` · `show vid <id>`                                      | Detail card (by id); vids also show the linked-game card                            |
| `delete` (alias `rm`) | `delete game <id>` · `delete video <id>`                                | Delete a game or vid (confirmation first)                                           |
| `link`                | `link video <id> to game <id>[,…]` · `link game <id> to video <id>[,…]` | Link a vid to a game (explicit, both directions)                                    |
| `unlink`              | `unlink video <id> from game <id>[,…]`                                  | Remove a video ↔ game link                                                          |
| `publish`             | `publish video <id>`                                                    | Set a vid public on YouTube (clears any schedule)                                   |
| `unlist`              | `unlist video <id>`                                                     | Set a vid unlisted on YouTube                                                       |
| `schedule`            | `schedule video <id> <when>` · `schedule <id> slate`                    | Schedule a future publish, or show the upcoming slate                               |
| `price`               | `price set <id> <amount>` · `price unset <id>`                          | Set/clear a game's euro price (> 0)                                                 |
| `footage`             | `footage update <id> <hours>` · `footage snippet`                       | Set a game's manual footage total, or copy an ffprobe one-liner                     |
| `platform`            | `platform <id> <name>`                                                  | Set a game's platform from free text (ps5, switch, steam)                           |
| `reindex`             | `reindex game <id>` · `reindex video <id>`                              | Re-embed in Voyage                                                                  |
| `import`              | `import game [title]` · `import vids [for @handle]`                     | Import a game from IGDB, or pull newer YouTube vids                                 |
| `sync`                | `sync vids [only id,…]` · `sync channels [with vids]`                   | Sync vids/channels from YouTube (scope via shift+tab)                               |
| `find`                | `find [<status>] [<genre>] [for <platform>]`                            | Search vids                                                                         |
| `help`                | `help`                                                                  | List every reply target and its actions                                             |

**`list games with <columns>`** — `platform`, `genre`, `developer`, `publisher`,
`channels`, `release`, `year`, `footage`, `price`. **`list vids with <columns>`** —
`channel`, `status`, `game`, `scheduled`, `length`, `views`, `likes`, `comments`.
Both accept `sorted by <column> [desc]`.

**`schedule … <when>`** (local, ≥30 min out): `today`, `today at 14:30`,
`today at 3am`, `in 30m`, `in 2 hours`, `in 3 days`, `tomorrow`, `tomorrow at noon`,
`tomorrow night`, `at 2pm`, `at 3:10am`, `at 23`, `at 15:30`, `saturday at noon`,
`next friday`, `next week`, `3 weeks from now`, `next month`, `for DD.MM.YYYY HH:MM`,
`DD-MM-YYYY HH:MM`. Keywords are case-insensitive (phone titleization is tolerated).

### Command language — replies (`#<handle> <action>`)

Repliable messages carry a `#<handle>`; reply to act on that message's subject.

| Surface      | Actions                                                                                                                                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Game detail  | `rm`/`delete`, `reindex`, `link to vid <id>[,…]`, `unlink from vid <id>[,…]`, `footage <hours>`, `platform <name>`, `price set <amount>` / `price unset`                                                           |
| Game list    | `show <id>`, `rm`/`delete <id>`, `add`/`remove <columns>`, `sort`/`order by <col> [desc]`, `link`/`unlink <game> to/from <vid>[,…]`                                                                                |
| Video detail | `rm`/`delete`, `reindex`, `link to game <id>[,…]`, `unlink from game <id>[,…]`                                                                                                                                     |
| Video list   | `show <id>`, `schedule <id> <when>` / `schedule <id> slate`, `publish <id>`, `unlist <id>`, `delete`/`rm <id>`, `add`/`remove <columns>`, `sort`/`order by <col> [desc]`, `link`/`unlink <vid> to/from <game>[,…]` |
| Channel list | `visit @handle`                                                                                                                                                                                                    |
| Confirmation | `confirm` (`yes`/`y`/`ok`) · `cancel` (`no`/`n`)                                                                                                                                                                   |

### Command language — slash commands

`/login <TOTP>`, `/logout`, `/new`, `/resume`, `/connect`, `/disconnect @handle`,
`/games import [title]`, `/themes`, `/help`, and `/config <provider> [key=value …]`
(providers: `google`, `voyage`, `igdb`, `webhook`, `sound`, `fx`, `timezone`).

### Notifications & integrations

- Rich Slack attachments + Discord embeds with a severity emoji + color
  (`info` / `success` / `warning` / `error`); new notification types plug in with
  zero webhook changes.
- New notifications broadcast their unread count to every open window live.
- Sources: YouTube reauth reminders, video-sync summaries, upcoming-release
  countdowns, and write-through rejections.

### Other UI/behaviour

- `:enhanced` segments share `:system`'s full render template (tables, sections);
  accent/background is the only difference.
- A reply that mutates a segment (sort / add column) lifts it onto the surface
  background as a "just changed" cue.
- Game-list **Channels** column is one line (`@first +N more`).
- Stats legend: `s` subs · `v` vids · `V` views · `L` likes · `C` comments.
- Per-conversation channel scope (shift+tab) + stats period (shift+space) persist
  across reloads.

### Removed

- The root `VERSION` file — versioning now lives in git tags + this changelog.
