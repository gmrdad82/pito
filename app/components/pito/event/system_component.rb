# frozen_string_literal: true

module Pito
  module Event
    # Renders a system-response event: surface-colored left bar, no background.
    # This is the default segment type emitted by slash command handlers.
    #
    # Payload keys (all optional unless noted):
    #   body:             [String]  — plain-text body rendered via typewriter reveal
    #   html:             [Boolean] — when true, `body` is pre-formatted HTML (no typewriter)
    #   text:             [String]  — fallback plain body when `body` is absent
    #   message_key:      [String]  — I18n key; resolved with `message_args` when `body`/`text` absent
    #   message_args:     [Hash]    — interpolation args for the I18n translation
    #   expand_lines:     [Array]   — condensed lines shown before expanding
    #   expand_detail:    [Array]   — additional lines shown after expanding
    #   expand_more_count:[Integer] — shown in "N more…" hint
    #   expand_label:     [String]  — overrides default expand hint text
    #   collapse_label:   [String]  — overrides default collapse hint text
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
        @expand_lines = Array(payload[:expand_lines]).map(&:to_s)
        @expand_detail = Array(payload[:expand_detail]).map(&:to_s)
        @expand_more_count = payload[:expand_more_count].to_i
        @table_rows   = Array(payload[:table_rows]).map { |r| r.respond_to?(:with_indifferent_access) ? r.with_indifferent_access : r }
        @info_lines   = Array(payload[:info_lines]).map(&:to_s)
        @sections     = Array(payload[:sections]).map { |s| s.respond_to?(:with_indifferent_access) ? s.with_indifferent_access : s }
        @suggestion      = payload[:suggestion]
        @handle          = payload[:handle].to_s.presence
        @channel         = payload[:channel].to_s.presence
        @reply_handle    = payload[:reply_handle].to_s.presence
        @reply_consumed  = Pito::FollowUp.consumed?(payload)
        @reply_target    = payload[:reply_target].to_s.presence
        @timestamp       = event&.created_at
      end

      attr_reader :body, :expand_lines, :expand_detail, :expand_more_count, :table_rows, :info_lines, :handle, :channel, :sections, :html, :reply_handle, :reply_consumed

      def expandable?    = @expand_detail.any? || @sections.any?
      def accent         = :surface
      def background     = nil

      # True when this system message has a follow-up handle and is not yet consumed.
      def followupable?
        @reply_handle.present? && !@reply_consumed
      end

      # Every follow-up-able message renders as a SINGLE meta line —
      # `timestamp · #handle`. There is NO separate usage/affordance line.
      # The reply handle flows into the meta line so the user sees the hashtag
      # to reply to; available actions live in /help, not in the message.
      def meta_handle
        handle.presence || (followupable? ? reply_handle : nil)
      end

      def expand_label
        @payload[:expand_label].presence || Pito::Copy.render("pito.copy.help.more_hint")
      end

      def collapse_label
        @payload[:collapse_label].presence || Pito::Copy.render("pito.copy.help.fewer_hint")
      end

      def render_info_line(line)
        segments = line.to_s.split(/(`[^`]+`)/)
        html = segments.map do |seg|
          if seg.start_with?("`") && seg.end_with?("`")
            content = ERB::Util.html_escape(seg[1..-2])
            %(<code class="text-fg">#{content}</code>)
          elsif seg.present?
            %(<span class="text-fg-dim">#{ERB::Util.html_escape(seg)}</span>)
          else
            ""
          end
        end.join
        html.html_safe
      end

      private

      # Returns a stable DOM id for anchorable system messages — those carrying
      # a follow-up engine handle (reply_handle present), which supersedes the old
      # `theme_list: true` flag. Also preserves `theme_diff: true` as an anchor
      # gate for backward-compat (ThemeDiffComponent still uses its own id helper,
      # but SystemComponent may receive a theme_diff payload during reload fallback).
      #
      # Returns nil when neither condition is met or when event is nil.
      def dom_id
        return nil unless @event

        anchorable = @reply_handle.present? ||
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
