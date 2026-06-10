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
    # Copy lives at pito.copy.hashtag_help.<indicator>:
    #   target_usage → pito.copy.hashtag_help.<indicator>.target_usage  (String)
    #   per-action   → pito.copy.hashtag_help.<indicator>.actions.<action>
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
        "channel_list"  => "list-channels",
        "confirmation"  => "confirm"
      }.freeze

      # @param target [String]       the reply_target string (e.g. "game_detail")
      # @param action [String, nil]  an action word (e.g. "footage") or nil for target page
      # @return [Hash, nil]          { "html" => true, "body" => "..." } or nil
      # Action aliases that share copy with another action.
      # "order" has no own copy block; it renders the "sort" page instead.
      ACTION_ALIASES = {
        "order" => "sort"
      }.freeze

      def call(target:, action: nil)
        handler = Pito::FollowUp::Registry.for(target.to_s)
        return nil unless handler
        return nil if handler.internal?

        indicator = TARGET_INDICATORS[target.to_s]
        return nil unless indicator

        if action
          normalized = ACTION_ALIASES.fetch(action.to_s, action.to_s)
          render_action_page(indicator, normalized)
        else
          render_target_page(indicator, handler)
        end
      end

      # ── Private ──────────────────────────────────────────────────────────────

      # Render the target-level page: usage + list of actions with their usage lines.
      def render_target_page(indicator, handler)
        target_usage = I18n.t("pito.copy.hashtag_help.#{indicator}.target_usage", default: nil)
        return nil unless target_usage.is_a?(String) && target_usage.present?

        # Collect action rows from the handler's declared actions.
        action_rows = handler.actions.filter_map do |act|
          data = I18n.t("pito.copy.hashtag_help.#{indicator}.actions.#{act}", default: nil)
          next unless data.is_a?(Hash)

          usage = (data[:usage] || data["usage"]).to_s
          next if usage.blank?

          [ act, usage ]
        end

        return nil if action_rows.empty?

        groups = [
          [ "Actions", action_rows ],
          [ "Options", [ [ "--help", "Print this help message" ] ] ]
        ]

        body = Pito::MessageBuilder::ManPage.render(usage: target_usage, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_target_page

      # Render an action-level page for a single action.
      def render_action_page(indicator, action)
        data = I18n.t("pito.copy.hashtag_help.#{indicator}.actions.#{action}", default: nil)
        return nil unless data.is_a?(Hash)

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
