module Pito
  module Notifications
    # Pito::Notifications::FilterChipsComponent — row of 4 category filter
    # chips for the notifications feed panel toolbar.
    #
    # Renders `[ ] channel  [ ] game  [ ] system  [ ] manual` chips in
    # section-accent color (bracket + label = one action per CLAUDE.md rules).
    # Each chip is a GET link that toggles the `?notifications_category=` URL
    # param. Clicking an active chip removes the filter (returns to "all").
    #
    # Chips are mutually exclusive: only one can be active at a time. The server
    # reads `?notifications_category=` on every paint — no localStorage.
    #
    # ## Kwargs
    #
    # @param active_category [String, nil] currently active category filter:
    #   "channel" | "game" | "system" | "manual" | nil (all chips unchecked).
    # @param frame_id [String] Turbo Frame ID wrapping the panel content.
    #   Passed through so each chip link targets the correct frame.
    # @param base_url [String] the URL to build chip links against (root_path
    #   or root_path with existing params). Category param is merged / removed.
    # @param filter [String] "unread" | "all" — forwarded to chip links so the
    #   unread filter survives a chip toggle.
    #
    # ## Focusables
    #
    # filter_chip_channel, filter_chip_game, filter_chip_system, filter_chip_manual
    # — used by the palette `click_focusable` dispatcher.
    #
    # ## Visual contract
    #
    # Bracket + label paint in var(--section-accent). Unchecked: `[ ] label`.
    # Checked: `[x] label`. This is ONE action per chip (bracket+label together).
    # Text between chips uses whitespace separator only (no delimiter chrome).
    class FilterChipsComponent < ViewComponent::Base
      CATEGORIES = %w[channel game system manual].freeze

      def initialize(active_category:, frame_id:, filter: "all", notifications_category: nil)
        @active_category = active_category.to_s.presence
        @frame_id        = frame_id
        @filter          = filter.to_s == "unread" ? "unread" : "all"
      end

      attr_reader :active_category, :frame_id, :filter

      # Build the link URL for a given chip category.
      # Toggling: if chip is already active → remove param (all). Else → set.
      def chip_url(cat, helpers)
        opts = {}
        opts[:notifications_feed_filter] = "unread" if filter == "unread"
        opts[:notifications_category]    = cat unless active_category == cat
        helpers.root_path(**opts)
      end

      # Is this chip currently active (checked)?
      def chip_active?(cat)
        active_category == cat
      end

      # Checkbox display string per chip state.
      def chip_box(cat)
        chip_active?(cat) ? "[x]" : "[ ]"
      end

      # CSS class for the chip link.
      def chip_css(cat)
        base = "nf-filter-chip"
        chip_active?(cat) ? "#{base} nf-filter-chip--active" : base
      end
    end
  end
end
