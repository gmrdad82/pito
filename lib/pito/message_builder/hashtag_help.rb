# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Two-level `--help` dispatcher for hashtag follow-up targets.
    #
    # HashtagHelp.call(target: "game_detail")
    #   → target-level page listing all actions for that target.
    #
    # HashtagHelp.call(target: "game_detail", action: "footage")
    #   → action-level page for the specific action.
    #
    # Copy lives at pito.hashtag_help.<indicator>:
    #   target_usage → pito.hashtag_help.<indicator>.target_usage  (String)
    #   per-action   → pito.hashtag_help.<indicator>.actions.<action>
    #                   = { usage:, sections: }
    #
    # Returns nil for:
    #   - internal targets (handler.internal? == true)
    #   - unknown targets (no indicator mapping or no copy)
    #   - unknown actions on a known target
    module HashtagHelp
      module_function

      # Maps reply_target string → i18n indicator (the key segment under hashtag_help.*).
      TARGET_INDICATORS = {
        "game_detail"   => "show-game",
        "game_list"     => "list-games",
        "video_detail"  => "show-video",
        "video_list"    => "list-videos",
        "video_search"  => "search-videos",
        "channel_list"  => "list-channels",
        "channel_detail" => "show-channel",
        "channel_games" => "channel-games",
        "confirmation"  => "confirm",
        "ai_message"    => "ai-answer"
      }.freeze

      # @param target [String]       the reply_target string (e.g. "game_detail")
      # @param action [String, nil]  an action word (e.g. "footage") or nil for target page
      # @param event  [Event, nil]   the source event; when supplied the universal share
      #                              tool rows are gated on Share existence for that event.
      # @return [Hash, nil]          { "html" => true, "body" => "..." } or nil
      # Action aliases that share copy with another action.
      # "order" has no own copy block; it renders the "sort" page instead.
      ACTION_ALIASES = {
        "order" => "sort",
        "vids"  => "videos",  # per-target reply alias of the `videos` tool
        "more"  => "next"     # per-target reply alias of the pager `next` tool
      }.freeze

      def call(target:, action: nil, event: nil)
        handler = Pito::FollowUp::Registry.for(target.to_s)
        return nil unless handler
        return nil if handler.internal?

        indicator = TARGET_INDICATORS[target.to_s]
        return nil unless indicator

        if action
          normalized = ACTION_ALIASES.fetch(action.to_s, action.to_s)
          render_action_page(indicator, normalized)
        else
          render_target_page(indicator, handler, event:)
        end
      end

      # ── Private ──────────────────────────────────────────────────────────────

      # Render the target-level page: usage + list of handler actions + universal
      # share tool rows (share always; revoke/unshare only when the event is shared).
      def render_target_page(indicator, handler, event: nil)
        target_usage = Pito::Copy.render_soft("pito.hashtag_help.#{indicator}.target_usage")
        return nil if target_usage.blank?

        # Collect action rows from Matrix (tools.yml — sole source of availability).
        action_rows = Pito::FollowUp::Registry.actions_for(handler.target_id).filter_map do |act|
          data = Pito::Copy.subtree("pito.hashtag_help.#{indicator}.actions.#{act}")
          next unless data

          usage = (data[:usage] || data["usage"]).to_s
          next if usage.blank?

          [ act, usage ]
        end

        # Universal share tool rows: share always, revoke/unshare when shared.
        share_rows = universal_share_tool_rows(event:)

        all_rows = action_rows + share_rows
        return nil if all_rows.empty?

        groups = [
          [ "Actions", all_rows ],
          [ "Options", [ [ "--help", "Print this help message" ] ] ]
        ]

        body = Pito::MessageBuilder::ManPage.render(usage: target_usage, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_target_page

      # Build the universal share tool rows for the help page.
      # share is always included; revoke/unshare only when the event has a Share.
      def universal_share_tool_rows(event:)
        tools = Pito::Share::UniversalActions.tools_for(event)
        tools.filter_map do |tool|
          desc = Pito::Copy.render_soft("pito.share_help.#{tool}")
          next if desc.blank?

          [ tool, desc ]
        end
      end
      private_class_method :universal_share_tool_rows

      # Render an action-level page for a single action.
      def render_action_page(indicator, action)
        data = Pito::Copy.subtree("pito.hashtag_help.#{indicator}.actions.#{action}")
        return nil unless data

        usage    = (data[:usage] || data["usage"]).to_s
        sections = data[:sections] || data["sections"]
        return nil if usage.blank? || !sections.is_a?(Hash)

        groups = build_groups(sections)
        return nil if groups.empty?

        body = Pito::MessageBuilder::ManPage.render(usage:, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_action_page

      # Convert I18n sections hash into ManPage groups array.
      def build_groups(sections)
        sections.filter_map do |title, rows|
          next unless rows.is_a?(Hash)

          [ title.to_s, rows.map { |tok, desc| [ tok.to_s, desc.to_s ] } ]
        end
      end
      private_class_method :build_groups
    end
  end
end
