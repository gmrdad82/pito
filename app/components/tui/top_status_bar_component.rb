module Tui
  # Beta 4 — Phase F1 Lane B. The top status bar. Locked visual matches
  # `tmp/demo-status-bar-final.html` (5 state variants V1-V5):
  #
  #   0.3.2-beta8 <section>[:(<page>)]         [<progress?>] <sync> | b<n> e<n> r<n> | <weekday>, <month> <day> · HH:MM:SS
  #
  # Left-fixed:  version (muted) + section (bold + section accent) +
  #              optional `:(<page>)` (parens muted, inner page name
  #              bold + bright).
  # Right-pushed via space-between: optional progress (bar + counter)
  #              + sync indicator (●/✗ + word + optional target) + `|`
  #              + Sidekiq cells (b/e/r) + `|` + live clock.
  #
  # Subscribes to `pito:status_bar` (see ADR 0017 + Lane A's
  # `StatusBarChannel` + `StatusBarBroadcastMiddleware`) for live
  # Sidekiq queue depth + sync state pushes; Lane C's
  # `tui_status_bar_controller.js` will hydrate the cells. The
  # data-* attributes on the rendered DOM are the contract between
  # this component (Lane B) and that controller (Lane C).
  #
  # Section accent (`--section-accent`) cascades via
  # `body[data-section]` (set by `current_section` in
  # `ApplicationHelper`) so the bar inherits the right color
  # automatically — no per-render section-to-color lookup needed here.
  #
  # Constructor inputs:
  #   - section:        required string (one of "home", "channels",
  #                     "games", "settings", "videos", "projects").
  #                     The CSS class `sb-section` always picks the
  #                     section accent via the cascading
  #                     `var(--section-accent)`, so passing the section
  #                     here is mostly cosmetic (label text) — the
  #                     class hook `.sb-section` is enough for color.
  #   - page:           optional string. When present, the `:(<page>)`
  #                     tail renders after the section label. `nil`
  #                     omits the tail entirely.
  #   - version:        optional string. Defaults to `Pito::VERSION`
  #                     for callers that don't pass one (mainly tests).
  #   - sidekiq_stats:  optional hash `{busy:, enqueued:, retry:,
  #                     scheduled:}`. Defaults to `{0, 0, 0, 0}`.
  #                     Cable pushes overwrite these in-place; the
  #                     initial render value is just the SSR first
  #                     paint.
  #   - sync_state:     one of `:idle`, `:syncing`,
  #                     `:syncing_with_target`, `:disconnected`.
  #                     Drives the dot glyph + sync word color + the
  #                     optional `sync_target` label. Defaults to
  #                     `:idle`.
  #   - sync_target:    optional string. Rendered immediately after
  #                     the sync word for `:syncing_with_target` (e.g.
  #                     "syncing channels" → target="channels"). Ignored
  #                     for other states.
  #   - progress:       optional hash `{current:, total:}`. Renders the
  #                     ASCII bar + counter when present. `nil` omits
  #                     the whole progress segment.
  class TopStatusBarComponent < ViewComponent::Base
    SYNC_STATES = %i[idle syncing syncing_with_target disconnected].freeze

    # Locked progress bar width (characters). 8 cells matches the demo
    # final reference (`▓▓▓░░░░░` for 12/33). Centralized here so the
    # template never inlines a literal.
    PROGRESS_BAR_WIDTH = 8

    def initialize(
      section:,
      page: nil,
      version: nil,
      sidekiq_stats: nil,
      sync_state: :idle,
      sync_target: nil,
      progress: nil
    )
      @section = section.to_s
      @page = page.presence
      @version = version.presence || default_version
      @sidekiq_stats = normalize_stats(sidekiq_stats)
      @sync_state = SYNC_STATES.include?(sync_state.to_sym) ? sync_state.to_sym : :idle
      @sync_target = sync_target.presence
      @progress = normalize_progress(progress)
    end

    attr_reader :section, :page, :version, :sidekiq_stats, :sync_state, :sync_target, :progress

    # Section accent class — used by tests + future cable hooks to
    # confirm the bar is wired to the right CSS cascade. The actual
    # color comes from `body[data-section]` cascade; this class is a
    # stable hook for the bold-weight `.sb-section` rule.
    def section_class
      "sb-section"
    end

    # Sidekiq cell color class — `sk-zero` (muted) when 0, otherwise
    # the per-letter color (sk-b green, sk-e orange, sk-r pink).
    def sidekiq_class_for(letter)
      value = @sidekiq_stats.fetch(letter_to_key(letter), 0)
      return "sk-zero" if value.zero?

      "sk-#{letter}"
    end

    def sidekiq_value_for(letter)
      @sidekiq_stats.fetch(letter_to_key(letter), 0)
    end

    # Sync dot glyph + class triple. Mirrors the demo:
    #   :idle                  -> ● green
    #   :syncing               -> ● amber
    #   :syncing_with_target   -> ● amber + sync_target rendered
    #   :disconnected          -> ✗ red (pink token)
    def sync_dot_glyph
      @sync_state == :disconnected ? "✗" : "●"
    end

    def sync_dot_class
      case @sync_state
      when :idle              then "sb-sync-dot sb-sync-dot--green"
      when :syncing, :syncing_with_target then "sb-sync-dot sb-sync-dot--amber"
      when :disconnected      then "sb-sync-dot sb-sync-dot--red"
      end
    end

    def sync_word
      case @sync_state
      when :idle              then "synced"
      when :syncing, :syncing_with_target then "syncing"
      when :disconnected      then "disconnected"
      end
    end

    def sync_word_class
      case @sync_state
      when :idle              then "sb-sync-word sb-sync-word--idle"
      when :syncing, :syncing_with_target then "sb-sync-word sb-sync-word--syncing"
      when :disconnected      then "sb-sync-word sb-sync-word--disconnected"
      end
    end

    def sync_target_visible?
      @sync_state == :syncing_with_target && @sync_target.present?
    end

    def progress_visible?
      !@progress.nil?
    end

    # ASCII progress bar — `PROGRESS_BAR_WIDTH` cells split between
    # filled (▓) and empty (░) per `current`/`total`. Returns
    # `[filled_string, empty_string]` so the template can color each
    # half separately (filled = fg, empty = muted).
    def progress_bar_cells
      total = @progress[:total].to_i
      current = @progress[:current].to_i
      return [ "", "░" * PROGRESS_BAR_WIDTH ] if total <= 0

      ratio = (current.to_f / total).clamp(0.0, 1.0)
      filled_count = (ratio * PROGRESS_BAR_WIDTH).round
      empty_count = PROGRESS_BAR_WIDTH - filled_count
      [ "▓" * filled_count, "░" * empty_count ]
    end

    def progress_counter
      "#{@progress[:current]}/#{@progress[:total]}"
    end

    private

    def default_version
      if defined?(::Pito) && ::Pito.const_defined?(:VERSION)
        ::Pito::VERSION
      else
        ""
      end
    end

    def normalize_stats(stats)
      base = { busy: 0, enqueued: 0, retry: 0, scheduled: 0 }
      return base if stats.nil?

      base.merge(stats.symbolize_keys.slice(:busy, :enqueued, :retry, :scheduled))
    end

    def normalize_progress(progress)
      return nil if progress.nil?

      h = progress.symbolize_keys
      current = h[:current].to_i
      total = h[:total].to_i
      return nil if total <= 0

      { current: current, total: total }
    end

    def letter_to_key(letter)
      case letter.to_s
      when "b" then :busy
      when "e" then :enqueued
      when "r" then :retry
      when "s" then :scheduled
      else letter.to_sym
      end
    end
  end
end
