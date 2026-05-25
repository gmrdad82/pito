module Tui
  # R10b (2026-05-25). Top status bar. Simplified to 3 slots:
  #
  #   [app version]    [empty center]    [ [ ] sync | DateTime ]
  #
  # Left:   Tui::AppVersionComponent — link to GitHub release tag
  # Center: empty (clean visual breathing room)
  # Right:  Tui::SyncIndicatorComponent — `[ ] sync` checkbox indicator
  #         + `|` pipe + Tui::DateTimeComponent — live wall clock
  #
  # Removed from TST (R10b):
  #   - Tui::BreadcrumbComponent   → moved to BST left zone (alongside mode lozenge)
  #   - Tui::TstNoticeComponent    → center slot is now blank
  #   - Tui::SidekiqStatsComponent → already moved to BST center in Phase 2 (2026-05-22)
  #   - Tui::HelpHintComponent     → moved to BST right zone
  #   - Tui::CommandHintComponent  → moved to BST right zone
  #
  # The parent owns the single ActionCable subscription to `pito:status_bar`
  # (via `tui_status_bar_controller.js`). On each payload the parent
  # controller dispatches `tui:sync-changed`; the sync child VC's own
  # Stimulus controller listens and patches its slot.
  #
  # Subscribes to: `pito:status_bar`
  # CABLE_CHANNEL: "pito:status_bar"
  # Focusables: none (chrome bar, not a panel)
  #
  # Constructor inputs:
  #   - section:     required string ("home", "videos", "games"). Used for
  #                  section-accent cascade context (forwarded to `section`
  #                  attr). No label rendered in TST since R10b.
  #   - version:     optional string. Defaults to `Pito::VERSION` for
  #                  callers that don't pass one (mainly tests); forwarded
  #                  to AppVersionComponent.
  #   - sync_state:  one of `:idle`, `:syncing`, `:syncing_with_target`,
  #                  `:disconnected`. Drives the `[ ] sync` glyph + color.
  #                  Defaults to `:idle`.
  #   - sync_target: optional string. Rendered for `:syncing_with_target`
  #                  state. Ignored for other states.
  #   - progress:    optional hash `{current:, total:}`. Renders the ASCII
  #                  bar + counter when present. `nil` omits the segment.
  #
  # Deprecated kwargs (accepted but unused since R10b):
  #   - page:           was the breadcrumb page tail; breadcrumb moved to BST.
  #   - sidekiq_stats:  was the Sidekiq cells; Sidekiq moved to BST center.
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
