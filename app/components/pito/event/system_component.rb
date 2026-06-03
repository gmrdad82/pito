# frozen_string_literal: true

module Pito
  module Event
    # System — default backend response. Surface-colored left bar, no background.
    # First segment emitted per turn. Supports expandable overflow (e.g. /help).
    class SystemComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload       = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload      = payload
        @body         = payload[:body].presence || resolve_text(payload)
        @html         = payload[:html] == true || payload[:html] == "true"
        @expand_lines = Array(payload[:expand_lines]).map(&:to_s)
        @expand_detail = Array(payload[:expand_detail]).map(&:to_s)
        @expand_more_count = payload[:expand_more_count].to_i
        @table_rows   = Array(payload[:table_rows]).map { |r| r.respond_to?(:with_indifferent_access) ? r.with_indifferent_access : r }
        @info_lines   = Array(payload[:info_lines]).map(&:to_s)
        @sections     = Array(payload[:sections]).map { |s| s.respond_to?(:with_indifferent_access) ? s.with_indifferent_access : s }
        @suggestion   = payload[:suggestion]
        @handle       = payload[:handle].to_s.presence
        @channel      = payload[:channel].to_s.presence
        @timestamp    = event&.created_at
      end

      attr_reader :body, :expand_lines, :expand_detail, :expand_more_count, :table_rows, :info_lines, :handle, :channel, :sections, :html

      def expandable?    = @expand_detail.any? || @sections.any?
      def accent         = :surface
      def background     = nil

      def expand_label
        @payload[:expand_label].presence || I18n.t("pito.slash.help.more_hint", count: expand_more_count)
      end

      def collapse_label
        @payload[:collapse_label].presence || I18n.t("pito.slash.help.fewer_hint")
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
