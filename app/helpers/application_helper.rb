module ApplicationHelper
  # 2026-05-19 — Section-variant theme key.
  #
  # Maps the current controller_path to one of four section buckets
  # that drive the Dracula section-variant accent system. The value is
  # rendered on `<body data-section="...">` (see
  # `app/views/layouts/application.html.erb`); CSS in
  # `app/assets/tailwind/application.css` reads the attribute to pick
  # `--color-section-accent` per section, which in turn flips the
  # derived `--color-bg` (4% accent tint over Dracula base) and
  # `--color-link` palette.
  #
  # Mapping (locked 2026-05-19, mirrors the CSS selectors and the
  # design.md table):
  #   home / dashboard / fallback -> "home"     (Dracula Purple)
  #   channels + videos           -> "channels" (Dracula Red)
  #   projects + games            -> "games"    (Pale Cobalt)
  #   settings                    -> "settings" (Dracula Orange)
  #
  # `controller_path` is matched both for top-level (e.g. `channels`,
  # `games`) and nested namespaces (e.g. `channels/stars`,
  # `settings/security/totp`, `games/destroy_confirms`) — the leading
  # segment alone determines the bucket. Anything else (root,
  # dashboard, notifications, calendar, ...) falls through to the
  # "home" default so the page renders with the Dracula Purple accent.
  #
  # 2026-05-20 — Auth-adjacent surfaces explicitly map to "settings"
  # so the orange accent carries through every credential / OAuth /
  # 2FA flow rather than flickering back to the home purple between
  # the navbar and the settings page proper. Covered surfaces and the
  # controllers that produce them:
  #   - `settings/*`                            — Settings::*Controller
  #     (includes `settings/security/totps`, `settings/webhooks/*`,
  #     `settings/sessions/*`, `settings/discord_webhooks`,
  #     `settings/slack_webhooks`, `settings/user`,
  #     `settings/time_zone`, `settings/notification_toggles`,
  #     `settings/security`)
  #   - `login/totp_challenges`                 — Login::TotpChallengesController
  #     (post-password TOTP step at `/login/totp`)
  #   - `password_resets`                       — PasswordResetsController
  #     (`/password/reset` family)
  #   - `doorkeeper/*`                          — Doorkeeper engine
  #     (`/oauth/authorize`, `/oauth/token`, `/oauth/revoke`,
  #     `/oauth/introspect`, `/oauth/applications` admin)
  #   - `oauth/registrations`                   — Oauth::RegistrationsController
  #     (MCP dynamic-client registration at `POST /oauth/register`)
  #   - `youtube_connections/oauth_callbacks`   —
  #     YoutubeConnections::OauthCallbacksController (Google OAuth
  #     redirect target for YouTube channel connections)
  def current_section
    return "home" unless respond_to?(:controller_path) && controller_path.present?

    path = controller_path

    if path == "login/totp_challenges" ||
       path == "password_resets" ||
       path == "oauth/registrations" ||
       path == "youtube_connections/oauth_callbacks" ||
       path.start_with?("settings", "doorkeeper/")
      return "settings"
    end

    case path
    when "channels", %r{\Achannels/}, "videos", %r{\Avideos/}
      "channels"
    when "games", %r{\Agames/}, "projects", %r{\Aprojects/}
      "games"
    else
      "home"
    end
  end

  # 2026-05-18 — Mobile-nav abbreviated labels dropped per user
  # decision. Both desktop and mobile now render the full bracketed
  # label (e.g. `[channels]`). The `short:` kwarg is retained for
  # call-site backward compatibility but is intentionally unused; the
  # `.show-mobile` short-label span is no longer emitted. Whole-group
  # `.hide-mobile` wrappers in the layout were also dropped so
  # `[home]` / `[calendar]` stay visible on mobile.
  def nav_link(label, path, short: nil, data: nil, muted: false)
    _ = short # retained for backward compatibility; ignored
    safe_label = ERB::Util.html_escape(label)

    # 2026-05-19 — `muted: true` renders a deactivated, non-clickable
    # bracketed text span for paused-zone navbar entries. Uses the
    # existing `.bracketed-muted` CSS class (bold + --color-muted +
    # cursor: default + user-select: none) defined in
    # `app/assets/tailwind/application.css`. The route stays intact
    # (still mounted in config/routes.rb); only the rendered link is
    # deactivated. Same visual footprint as the live link so the
    # surrounding nav-row layout doesn't shift.
    if muted
      return content_tag(:span, class: "bracketed bracketed-muted") do
        ("[" + safe_label + "]").html_safe
      end
    end

    prefix = path.chomp("/")
    active = current_page?(path) || (prefix.present? && request.path.start_with?(prefix + "/"))

    if active
      content_tag(:span, class: "bracketed bracketed-active") do
        ("[" + safe_label + "]").html_safe
      end
    else
      # `data:` is forwarded to the underlying `link_to` so callers can
      # wire Stimulus `data-action` / `data-controller` declarations onto
      # the bracketed link without abandoning the helper (used by the
      # navbar `[notifications]` entry to open the layout-level
      # notifications modal in lieu of a full-page navigation).
      opts = { class: "bracketed" }
      opts[:data] = data if data.present?
      link_to(path, opts) do
        ("[<span class=\"bl\">" + safe_label + "</span>]").html_safe
      end
    end
  end

  # 2026-05-20 — Per-section bg / accent helpers. Read from
  # `Pito::Theme::Sections` so the values are specced and unified across
  # the Rails layout AND any future server-rendered surface that needs
  # the same colors (CLI status preview, OG card renderer, etc.).
  # The layout calls these in the inline `<body style="...">` so the
  # browser receives Ruby-computed hex instead of resolving a CSS
  # `color-mix()` chain at paint time.
  def pito_section_bg(section = current_section)
    Pito::Theme::Sections.bg(section)
  end

  def pito_section_accent(section = current_section)
    Pito::Theme::Sections.accent(section)
  end

  def breadcrumb(*crumbs)
    content_for(:breadcrumbs) do
      render(BreadcrumbComponent.new(crumbs: crumbs))
    end
  end

  def view_trend_indicator(video)
    stats = video.video_stats.order(date: :desc).limit(7).pluck(:views)
    return render(StatusIndicatorComponent.new(kind: :flat, text: "—")) if stats.size < 2

    recent = stats.first(3).sum.to_f / [ stats.first(3).size, 1 ].max
    older = stats.last(3).sum.to_f / [ stats.last(3).size, 1 ].max
    return render(StatusIndicatorComponent.new(kind: :flat, text: "—")) if older.zero?

    change = ((recent - older) / older * 100).round(0)
    if change > 5
      render(StatusIndicatorComponent.new(kind: :up, text: "#{change}% ▲", sort_value: change))
    elsif change < -5
      render(StatusIndicatorComponent.new(kind: :down, text: "#{change.abs}% ▼", sort_value: change))
    else
      render(StatusIndicatorComponent.new(kind: :flat, text: "— flat", sort_value: 0))
    end
  end

  def format_duration(seconds)
    return "—" unless seconds&.positive?
    hours = seconds / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60
    if hours > 0
      format("%d:%02d:%02d", hours, mins, secs)
    else
      format("%d:%02d", mins, secs)
    end
  end

  def format_video_watch_time(minutes)
    return "—" unless minutes&.positive?
    hours = (minutes / 60.0).round
    "#{number_with_delimiter(hours)}h"
  end

  # Phase 14 §1 — time-to-beat formatter. IGDB returns seconds; we
  # display "Xh Ym" (or "—" when the field is nil / non-positive).
  def format_seconds(seconds)
    return "—" unless seconds.is_a?(Integer) && seconds.positive?
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    if hours.positive?
      minutes.zero? ? "#{hours}h" : "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  # Render a sortable column header as a `link_to` whose URL flips the
  # `sort` / `dir` query params while preserving every other URL param
  # (filter chips, saved-view selectors, etc.). The active sort column's
  # link carries a `.sort-asc` / `.sort-desc` class; the directional
  # arrow is rendered exclusively by CSS via the `::after`
  # pseudo-element on the parent `th.sortable` (see the `:has()` rule
  # in `app/assets/tailwind/application.css`). The link text itself is
  # ALWAYS just the bare label — active and inactive headers share the
  # same rendering pipeline so they line up at the pixel level.
  #
  # Used by the index pages whose order is driven by URL state — see
  # `ChannelsController` and `VideosController`. The `/projects` index
  # predates this helper and ships its own inline lambda; the helper is
  # written so it could absorb that view later without behavior change.
  #
  # `current_sort` / `current_dir` come from the controller (`@sort` /
  # `@dir`) so the indicator and the next-direction calculation reflect
  # what the page is actually rendering, not the raw `params`.
  #
  # `sort_param:` / `dir_param:` allow a page to host more than one
  # independently sortable table. The project show page, for example,
  # hosts both a footage table (default `sort` / `dir` params) and a
  # notes table (namespaced `notes_sort` / `notes_dir`) — passing
  # `sort_param: "notes_sort", dir_param: "notes_dir"` keeps each
  # table's URL state distinct while preserving the other's params on
  # each click.
  #
  # Dual-arrow fix (2026-05-06, refined 2026-05-06 polish-2): the active
  # column's link carries a `.sort-asc` / `.sort-desc` class. The
  # `th.sortable::after` neutral indicator is rendered by CSS
  # unconditionally on every sortable header; the
  # `:has(a.sort-asc | a.sort-desc)` rule in
  # `app/assets/tailwind/application.css` overrides the neutral
  # `▲\A▼` stack with a single directional glyph (`▲` or `▼`) on the
  # active column. The arrow is NOT rendered as inline text inside the
  # link — it rides exclusively through the CSS pseudo-element so the
  # active and inactive states share the same rendering pipeline (same
  # absolute-positioned `::after`, same `right: 1px` offset, same
  # font-size). Inline-text arrows produced misaligned glyphs and a
  # trailing space artefact next to active headers.
  #
  # `frame:` opts the link into Turbo Frame navigation. When set, the
  # link carries `data-turbo-frame="<frame-id>"` so Turbo only swaps
  # the matching `<turbo-frame>` element from the response (rather than
  # navigating the whole page) AND `data-turbo-action="advance"` so the
  # browser URL still updates and back/forward navigation works. The
  # frame on the page MUST share its `id` with the frame in the
  # response — otherwise Turbo aborts the swap and falls back to a
  # full-page navigation. Combined with morph (set globally in the
  # layout's `<meta name="turbo-refresh-method" content="morph">`), a
  # framed sort click preserves scroll position and form state while
  # only the frame's contents re-render.
  def sort_link_to(label, key, current_sort:, current_dir:, sort_param: "sort", dir_param: "dir", frame: nil)
    next_dir = (current_sort == key && current_dir == "asc") ? "desc" : "asc"
    active = current_sort == key
    data = {}
    if frame
      data[:turbo_frame] = frame
      data[:turbo_action] = "advance"
    end
    link_to(
      label,
      request.query_parameters.merge(sort_param => key, dir_param => next_dir),
      class: active ? "sort-#{current_dir}" : nil,
      data: data
    )
  end

  def cancel_path_for(type)
    case type
    when "channel"    then channels_path
    when "video"      then videos_path
    when "project"    then projects_path
    when "game"       then games_path
    # Notes/timelines have no top-level user-facing index — fall back to
    # the projects index, the closest reasonable parent.
    when "note"       then projects_path
    when "timeline"   then projects_path
    # 2026-05-18 — `/bundles` index removed. Bundles are reachable
    # only via the /games bundle shelf + modal flow; cancel/back
    # destinations fall back to /games.
    when "bundle"     then games_path
    when "video_game_link" then videos_path
    else root_path
    end
  end

  def app_version
    @_app_version ||= Rails.root.join("VERSION").read.strip
  end

  # Beta 4 — Phase F1 Lane B. The top status bar's leading version label.
  # Aliases `app_version` so the status bar reads from the same canonical
  # `VERSION` file source as the About modal (no duplicate
  # source-of-truth). Kept as a distinct helper name so a future shift
  # (e.g. `vX.Y.Z` for release) can diverge from the underlying
  # `app_version` without churning every status-bar call site.
  def pito_version
    app_version
  end

  # Beta 4 — Phase F1 Lane B. The top status bar's optional `:(<page>)`
  # tail. Returns the human-readable name of the current sub-page WHEN
  # the route is a sub-page deeper than the section's root index. Returns
  # `nil` for section root screens (e.g. `/channels`, `/settings`,
  # `/home`) so the status bar renders just `<version> <section>` without
  # a trailing `:(...)` segment.
  #
  # Resolution rules (locked 2026-05-20 with the tmp/demo-status-bar-final
  # visual):
  #   - `games#show`     -> @game.title (e.g. "Witcher 3: Wild Hunt")
  #   - `channels#show`  -> @channel.title or @channel.handle or url tail
  #   - `videos#show`    -> @video.title
  #   - `projects#show`  -> @project.name
  #   - anything else    -> nil (no `:(...)` segment)
  #
  # We deliberately depend on the controller's instance variables here
  # because the layout renders AFTER the controller's action has set
  # them; reaching into `@game` / `@channel` keeps the helper view-only
  # and avoids re-querying the DB just to produce a label.
  def current_page
    return nil unless respond_to?(:controller_path) && controller_path.present?
    return nil unless respond_to?(:action_name) && action_name == "show"

    case controller_path
    when "games"
      game = instance_variable_get(:@game)
      game.respond_to?(:title) ? game.title.presence : nil
    when "channels"
      channel = instance_variable_get(:@channel)
      return nil unless channel

      title = channel.respond_to?(:title) ? channel.title : nil
      handle = channel.respond_to?(:handle) ? channel.handle : nil
      title.presence || handle.presence
    when "videos"
      video = instance_variable_get(:@video)
      video.respond_to?(:title) ? video.title.presence : nil
    when "projects"
      project = instance_variable_get(:@project)
      project.respond_to?(:name) ? project.name.presence : nil
    end
  end

  # Beta 4 — Phase F1 Lane B. Initial-paint snapshot of Sidekiq queue
  # depths consumed by `Tui::TopStatusBarComponent`. The cable channel
  # (`pito:status_bar`, see `StatusBarBroadcastMiddleware`) pushes the
  # same shape on every job completion so the four cells (b/e/r/s) only
  # need a sensible value for the very first paint before cable wakes
  # up. Returns muted-zero defaults if Sidekiq::Stats raises (test envs
  # that mock Redis, transient Redis blips, etc.) — the page is never
  # blocked on Sidekiq.
  def sidekiq_queue_stats
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    {
      busy: stats.workers_size,
      enqueued: stats.enqueued,
      retry: stats.retry_size,
      scheduled: stats.scheduled_size
    }
  rescue StandardError
    { busy: 0, enqueued: 0, retry: 0, scheduled: 0 }
  end

  def pane_breadcrumb_label(panes, show: 3, trunc_length: 14)
    return label_for_pane(panes.first) if panes.size == 1

    shown = panes.first(show)
    extra = panes.size - show

    labels = shown.map do |pane|
      truncate(label_for_pane(pane), length: trunc_length, omission: "…")
    end

    labels << "+#{extra} more" if extra > 0

    labels.join(" · ")
  end

  def label_for_pane(pane)
    return "unknown" if pane.nil?
    return pane.title if pane.respond_to?(:title) && pane.try(:title).present?
    return "##{pane.id}" if pane.respond_to?(:id)
    "unknown"
  end

  # Initial-paint palette for Chartkick / Chart.js. Mirrors the
  # --color-chart-1..5 CSS custom properties. The client-side
  # `recolorCharts` reader (in `application.js`) replaces these with
  # the live CSS-var values shortly after first paint, so this helper
  # exists only to give the initial pre-recolor frame design-system
  # colors instead of Chart.js defaults. Keep in sync with
  # `--color-chart-N` in `app/assets/tailwind/application.css`.
  # (Theme system removed 2026-05-19 — pito is single-theme now.)
  CHART_PALETTE = %w[#0000cc #2e7d32 #8b5cf6 #d97706 #0891b2].freeze

  def chart_palette(count = CHART_PALETTE.length)
    CHART_PALETTE.first(count)
  end

  # Server-side fixed-length middle truncation. Returns a single string
  # with a Unicode ellipsis (U+2026) joining the leading `head` chars
  # and the trailing `tail` chars; the input is returned as-is when it
  # is short enough that truncation would not actually shorten it
  # (i.e. `length <= head + 1 + tail`).
  #
  # Used by the `/channels` and `/videos` index URL cells to keep the
  # YouTube channel ID (the unique tail of
  # `https://www.youtube.com/channel/<id>`) visible while collapsing
  # the boilerplate prefix to `https://…<id>`. The footage filename
  # column shares the same shape via `FootageHelper#filename_truncate_middle`,
  # which delegates here. Caller chooses `head:` / `tail:`; nothing is
  # generic about the choice, so it lives at the call site.
  ELLIPSIS = "…".freeze # Unicode U+2026 — single character, NOT `...`.

  def middle_truncate(str, head:, tail:)
    s = str.to_s
    return "" if s.empty?
    return s if s.length <= head + 1 + tail
    "#{s[0...head]}#{ELLIPSIS}#{s[-tail..]}"
  end

  # Phase B post-commit (2026-05-04) — Note revamp. Server-side markdown
  # rendering used as the SSR fallback for the note editor's preview pane:
  # the page paints with the rendered HTML; `marked.js` then takes over on
  # `input` events client-side and updates the same node live. Commonmarker
  # already ships with the repo (Gemfile.lock); we use its plain
  # `to_html` with safe defaults — the `unsafe_` extensions are NOT enabled,
  # so raw HTML in the source is escaped.
  #
  # Phase 26 — 01d. `plain:` keyword toggles a stripped-down render path
  # used by the webhook help guides (`Settings::Webhooks::HelpController`):
  # no header anchor links, no inline-styled syntax highlighting. The
  # help-modal CSS handles its own typography; the markdown source ships
  # generic `<h1>` / `<h2>` / `<pre>` / `<code>` so the modal can style
  # consistently and the spec assertions stay readable.
  #
  # 2026-05-16 polish — `target_external_links:` keyword post-processes
  # the rendered HTML so every `<a>` rendered in markdown picks up
  # pito's bracketed-link visual treatment AND every absolute
  # `http(s)://` anchor additionally gets `target="_blank"` plus
  # `rel="noopener noreferrer"`. The pito hard rule (see
  # `docs/design.md` → "External links — new tab") is that any link
  # leaving the pito app opens in a new tab so the user isn't yanked out
  # of their workspace; `noopener noreferrer` closes the `window.opener`
  # and Referer leak windows. The bracketed-link convention is the other
  # half of the rule — every clickable element in pito reads as
  # `[ label ]`, including links rendered from markdown source.
  #
  # Pass this from surfaces that render curated markdown whose links
  # should match the rest of the app's chrome (the webhook help guides
  # today; future settings help guides tomorrow). The note editor
  # preview intentionally does NOT pass this so notes stay same-tab and
  # un-bracketed — notes are scratch space typed live by the user; the
  # bracket chrome would fight the live `marked.js` client preview that
  # ships plain anchors.
  def render_markdown(text, plain: false, target_external_links: false)
    return "".html_safe if text.blank?

    html =
      if plain
        # `header_ids: nil` disables the `<a class="anchor">` injection
        # that Commonmarker enables by default. `plugins: { syntax_highlighter: nil }`
        # disables the inline-styled `<pre style="background-color:…">` wrapper.
        # `hardbreaks: true` keeps a single `\n` as `<br>` — beginner-friendly
        # guides rely on the visual line breaks.
        #
        # `table: true` enables GFM tables — the webhook help guides use
        # them in the Troubleshooting section so the error-meaning-fix
        # mapping reads cleanly as a grid instead of a dense paragraph.
        Commonmarker.to_html(
          text.to_s,
          options: { extension: { header_ids: nil, table: true }, render: { hardbreaks: true } },
          plugins: { syntax_highlighter: nil }
        )
      else
        # `hardbreaks: true` makes a single `\n` render as `<br>` instead of
        # collapsing into the surrounding paragraph (CommonMark default). Matches
        # the `breaks: true` flag set on `marked` client-side so SSR and live
        # rendering produce identical output.
        Commonmarker.to_html(
          text.to_s,
          options: { render: { hardbreaks: true } }
        )
      end

    html = decorate_links(html) if target_external_links
    html.html_safe
  end

  # Post-processes a fragment of HTML (typically produced by
  # `render_markdown`) so every anchor it contains adopts pito's
  # bracketed-link visual chrome AND every absolute `http(s)://` anchor
  # additionally carries `target="_blank"` + `rel="noopener noreferrer"`.
  #
  # Bracketing (applied to ALL anchors, internal and external):
  #   - `class="bracketed"` is appended to whatever classes the anchor
  #     already carries — never replaces them. The CSS rule lives in
  #     `app/assets/tailwind/application.css` and matches the
  #     `BracketedLinkComponent` markup.
  #   - The anchor's inner HTML is wrapped in literal `[` + a
  #     `<span class="bl">…</span>` around the original content + `]`,
  #     mirroring the markup `BracketedLinkComponent` and
  #     `ApplicationHelper#nav_link` emit. Inner HTML (not text) is
  #     preserved so an emphasized markdown link like `[*x*](…)` keeps
  #     its `<em>` wrapping inside the `.bl` span.
  #
  # External-link decoration (absolute `http://` or `https://` only):
  #   - `target="_blank"` opens the destination in a new tab so the
  #     user isn't yanked out of their pito workspace.
  #   - `rel` gains both `noopener` (closes the `window.opener` handle
  #     so the destination can't reach back into the source tab) and
  #     `noreferrer` (drops the `Referer` header so the destination
  #     can't learn which pito URL sent the user). Existing `rel`
  #     tokens are preserved; duplicates are folded out.
  #
  # Relative hrefs (`/foo`, `#section`, `mailto:…`, `tel:…`) keep
  # default same-tab behavior — only the bracket chrome is added.
  def decorate_links(html_fragment)
    fragment = Nokogiri::HTML5.fragment(html_fragment)
    fragment.css("a[href]").each do |anchor|
      existing_classes = anchor["class"].to_s.split
      anchor["class"] = (existing_classes + [ "bracketed" ]).uniq.join(" ")

      bl_span = Nokogiri::XML::Node.new("span", fragment)
      bl_span["class"] = "bl"
      bl_span.inner_html = anchor.inner_html
      anchor.inner_html = "[#{bl_span.to_html}]"

      href = anchor["href"].to_s
      next unless href.match?(/\Ahttps?:\/\//i)

      anchor["target"] = "_blank"
      existing_rel = anchor["rel"].to_s.split.map(&:downcase)
      merged = (existing_rel + %w[noopener noreferrer]).uniq
      anchor["rel"] = merged.join(" ")
    end
    fragment.to_html
  end

  # Integer-only byte formatter for the /settings stack pane tables
  # (Postgres / Redis / Meilisearch / assets / notes breakdowns).
  #
  # Differs from `FootageHelper#human_filesize` in two ways:
  #   1. KB is the smallest unit shown — `0` and any value below 1 KB
  #      still render as `"0 KB"` / `"1 KB"`, never `"512 Bytes"`.
  #   2. Always integer (no fractional digits). `1.43 KB` -> `"1 KB"`,
  #      `49.8 KB` -> `"50 KB"`, `192_000` bytes -> `"188 KB"`.
  #
  # `nil` returns the em-dash placeholder Pito uses for "no value".
  # `0` returns `"0 KB"` here (legitimate zero — the stack pane's
  # storage / index probes always report a real number, never "not
  # probed yet"; the footage helper's 0-as-em-dash semantics don't
  # apply to dashboard counters).
  STACK_SIZE_UNITS = %w[KB MB GB TB PB].freeze

  def human_filesize_int(bytes)
    return "—" if bytes.nil?
    n = bytes.to_f / 1024.0
    unit_index = 0
    while n >= 1024 && unit_index < STACK_SIZE_UNITS.length - 1
      n /= 1024.0
      unit_index += 1
    end
    "#{n.round} #{STACK_SIZE_UNITS[unit_index]}"
  end
end
