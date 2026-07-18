# frozen_string_literal: true

module Pito
  module Event
    # Renders a system-response event: surface-colored left bar, no background.
    # This is the default segment type emitted by slash command handlers.
    #
    # Payload keys (all optional unless noted):
    #   body:             [String]  — plain-text body, rendered instantly (no reveal)
    #   html:             [Boolean] — when true, `body` is pre-formatted HTML
    #   text:             [String]  — fallback plain body when `body` is absent
    #   message_key:      [String]  — I18n key; resolved with `message_args` when `body`/`text` absent
    #   message_args:     [Hash]    — interpolation args for the I18n translation
    #   expand_detail:    [Array]   — detail rows, rendered always-visible (as `detail`)
    #   table_rows:       [Array]   — key/value rows rendered as a definition table
    #   info_lines:       [Array]   — lines rendered with inline `code` highlighting
    #   sections:         [Array]   — titled section blocks (title + rows)
    #   suggestion:       [Object]  — segment suggestion payload forwarded to SegmentSuggestionComponent
    #   handle:           [String]  — channel handle shown in the meta line
    #   channel:          [String]  — channel name shown in the meta line
    class SystemComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload       = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload      = payload
        @event        = event
        @body         = payload[:body].presence || resolve_text(payload)
        @html         = payload[:html] == true || payload[:html] == "true"
        @expand_detail = Array(payload[:expand_detail]).map(&:to_s)
        @table_rows   = Array(payload[:table_rows]).map { |r| r.respond_to?(:with_indifferent_access) ? r.with_indifferent_access : r }
        @table_heading    = payload[:table_heading].presence
        @shimmer_heading  = payload[:shimmer_heading] == true || payload[:shimmer_heading] == "true"
        @fixed_leading    = payload[:fixed_leading].to_i
        @fixed_trailing   = payload[:fixed_trailing].to_i
        @info_lines   = Array(payload[:info_lines]).map(&:to_s)
        @sections     = Array(payload[:sections]).map { |s| s.respond_to?(:with_indifferent_access) ? s.with_indifferent_access : s }
        @suggestion      = payload[:suggestion]
        @handle          = payload[:handle].to_s.presence
        @channel         = payload[:channel].to_s.presence
        @reply_handle    = payload[:reply_handle].to_s.presence
        @reply_consumed  = Pito::FollowUp.consumed?(payload)
        @reply_target    = payload[:reply_target].to_s.presence
        @list_footer     = payload[:list_footer].to_s.presence
        @timestamp       = event&.created_at
      end

      attr_reader :body, :expand_detail, :table_rows, :table_heading, :shimmer_heading,
                  :info_lines, :handle, :channel, :sections, :html, :reply_handle, :reply_consumed,
                  :fixed_leading, :fixed_trailing, :list_footer

      def accent         = :surface

      # Always transparent (left bar only). Replies/follow-ups no longer elevate a
      # message onto the surface background — the payload[:surface] "just changed by
      # your reply" lift was removed. Messages that come surfaced
      # do so via their own component (e.g. *_follow_up), not via this flag.
      def background = nil

      # True when this system message has a follow-up handle, is not yet
      # consumed, AND — when a persisted event backs this render — currently
      # has at least one available reply action. That last check is the
      # owner's "no actions → no handle, no chip" rule
      # (Pito::FollowUp.renderable_actions?): a re-render of an OLD event
      # whose actions have since gone away (its origin tool opted out, or its
      # target lost its actions) simply comes back chipless — payloads are
      # data, re-render yields current rules, no special-casing needed.
      # Payload-only renders with no @event (component-level specs) skip that
      # extra check — there's no persisted kind to evaluate it against.
      def followupable?
        return false unless @reply_handle.present? && !@reply_consumed

        @event.nil? || Pito::FollowUp.renderable_actions?(@event)
      end

      # Every follow-up-able message renders as a SINGLE meta line —
      # `timestamp · #handle`. There is NO separate usage/affordance line.
      # The reply handle flows into the meta line so the user sees the hashtag
      # to reply to; available actions live in /help, not in the message.
      def meta_handle
        handle.presence || (followupable? ? reply_handle : nil)
      end

      # True when the message may carry a meta line at all — the template then
      # emits the `data-pito-meta-slot` div and the serve-time filler renders
      # the CURRENT meta state (liveness included) into it. Keyed off the
      # stable payload facts (handle present / channel present / a reply_handle
      # exists), NOT off consumption state — so the cached fragment never
      # changes when a handle retires.
      def meta_slot?
        handle.present? || channel.present? || reply_handle.present?
      end

      # Returns table_rows as an array of cell arrays: each row becomes an ordered
      # Array of { text:, class: } hashes (or { score:, class: } — see below).
      # Supports the new `:cells` key (arbitrary N columns) and falls back to
      # the legacy { key:, value:, value2: } shape so every existing caller
      # renders identically.
      #
      # A `:cells` entry may carry `score:` (Integer 0..100) instead of
      # `text:` to render a score bar — see #normalized_cell.
      #
      # A row may also carry an opaque row-level `:data` key (a sibling of
      # `:cells`) — arbitrary HTML data-* attributes a handler wants stamped
      # onto its row. The data-grid has no single per-row DOM element (rows
      # are flat sibling grid-item spans laid out by CSS grid, not wrapped in
      # a row `<div>` — see `.pito-data-grid` in application.css), so "the row
      # carries an attribute" means every cell span of that row carries it.
      # Domain-agnostic and reusable by any handler/builder emitting
      # `cells`-shaped rows, not specific to any one caller. Per-cell `:data`
      # (set on an individual cell) wins over the row-level value on key
      # collision. Rows without a `:data` key render byte-identical to before.
      def normalized_table_rows
        @normalized_table_rows ||= table_rows.map do |row|
          if row[:cells].present?
            row_data = row[:data].presence
            row[:cells].map { |c| normalized_cell(c, row_data) }
          else
            cells = [
              { text: row[:key].to_s,   class: "#{row.fetch(:key_class, 'text-cyan')} whitespace-nowrap" },
              { text: row[:value].to_s, class: row.fetch(:value_class, "text-fg-dim").to_s }
            ]
            cells << { text: row[:value2].to_s, class: "text-cyan whitespace-nowrap" } if row[:value2].present?
            cells
          end
        end
      end

      # Returns the data-grid column count (clamped to a 2-column minimum) for
      # the `data-cols` attribute, which selects the matching static CSS rule
      # in `.pito-data-grid[data-cols="N"]`. No inline style.
      def table_col_count(n)
        [ n, 2 ].max
      end

      # Returns heading cell hashes (one per label) when table_heading is present,
      # or an empty array when absent. Heading cells render instantly (no typewriter).
      #
      # Each entry in +table_heading+ may be either:
      #   - a String   → base class only
      #   - a Hash with "text" / "class" keys → extra class appended to the base class
      def table_heading_cells
        return [] if table_heading.blank?

        base = "text-fg-faded whitespace-nowrap"
        Array(table_heading).map do |entry|
          if entry.is_a?(Hash)
            h    = entry.respond_to?(:with_indifferent_access) ? entry.with_indifferent_access : entry
            text = h["text"].to_s
            extra = h["class"].presence
            { text:, class: heading_class(base, extra, text) }
          else
            text = entry.to_s
            { text:, class: heading_class(base, nil, text) }
          end
        end
      end

      # The legacy "added column" affordance class (cyan, !important). It used to
      # tint the dynamic `with`-columns so they read as distinct from the fixed
      # #/Title columns — predating the shimmer-heading feature. It is stripped
      # here so EVERY sortable heading (fixed AND added) shares ONE appearance:
      # the cyan shimmer is the sole live affordance, and a consumed list drops
      # cleanly to plain muted (no leftover cyan).
      HEADING_AFFORDANCE_CLASS = "pito-table-heading--added"

      # Composes a heading-cell class. Table headings are ALWAYS PLAIN muted text:
      # no shimmer, no bold, no cyan — in BOTH the live and the
      # reply_consumed states. The rule is "only action / thinking / network /
      # subject / reference shimmer; everything else is plain", and a column
      # heading is none of those. Only layout-affecting extras (e.g. `text-right`)
      # survive; the legacy `pito-table-heading--added` colour class is dropped so
      # added columns never linger cyan.
      def heading_class(base, extra, _text)
        layout = Array(extra&.split).reject { |c| c == HEADING_AFFORDANCE_CLASS }
        [ base, *layout ].compact.join(" ")
      end

      private

      # Normalizes one :cells entry into the shape DataGridComponent renders.
      #
      # A cell may carry `score:` (Integer 0..100) INSTEAD of `text:` — that
      # renders the SAME score bar the similar-games / channel-recommendation
      # cards use (Pito::ScoreBarComponent), built from the numeric value at
      # DISPLAY time (see DataGridComponent#render_score_cell) — the event
      # payload only ever stores the integer, never the bar's HTML, so a
      # re-render always reflects the current bar styling/translations. The
      # `pito-cell-score` wrapper class (grid-column width cap) is added
      # automatically; any caller-supplied `class:` is appended alongside it.
      # A cell without `score:` renders exactly as before (byte-identical).
      def normalized_cell(c, row_data)
        data = merged_cell_data(c[:data], row_data)
        return { score: c[:score].to_i, class: [ "pito-cell-score", c[:class] ].compact.join(" "), data: } if c[:score].present?

        { text: c[:text].to_s, class: c[:class].presence || "text-fg-dim", html: c[:html] == true, data: }
      end

      # Merges a row's opaque `:data` hash onto one cell's own `:data` hash —
      # cell wins on key collision. Returns `cell_data.presence` unchanged
      # when the row carries no `:data` (the pre-existing expression, so
      # every row without the new key renders byte-identical), else a plain
      # Hash so `tag.span`'s `data:` option (Pito::Event::DataGridComponent
      # #render_cell_span) dasherizes every key the same way regardless of
      # source.
      def merged_cell_data(cell_data, row_data)
        return cell_data.presence if row_data.blank?

        row_data.to_h.merge((cell_data.presence || {}).to_h)
      end

      # Returns a stable DOM id for anchorable system messages.
      #
      # A message is anchorable when any of the following is true:
      #   - reply_handle is present (standard user-facing follow-up messages)
      #   - anchor: true (internal machine-flow messages, e.g. channel_visit)
      #   - theme_diff: true (backward-compat for ThemeDiffComponent fallback)
      #
      # Returns nil when none of the conditions is met or when event is nil.
      def dom_id
        return nil unless @event

        anchorable = @reply_handle.present? ||
                     @payload[:anchor]     == true || @payload[:anchor]     == "true" ||
                     @payload[:theme_diff] == true || @payload[:theme_diff] == "true"
        "event_#{@event.id}" if anchorable
      end

      def resolve_text(payload)
        if payload[:message_key]
          I18n.t(payload[:message_key], **payload.fetch(:message_args, {}))
        else
          payload[:text]
        end
      end
    end
  end
end
