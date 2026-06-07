# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Theme
      # Builds the payload for the theme list message.
      #
      # Returns a sections payload listing Dark and Light theme groups.
      # The currently active theme is marked with a value2 marker (rendered in
      # cyan by the system component). Stamped follow-up-able
      # (reply_target: "theme_list") so the user can reply
      # `#<handle> preview <name>` / `#<handle> apply <name>`.
      module List
        module_function

        # @param grouped      [Hash]   result of Pito::Themes::Registry.grouped.
        # @param current_slug [String] the slug of the currently active theme.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] string-keyed payload with body, sections, and follow-up fields.
        def call(grouped:, current_slug:, conversation:)
          dark_rows  = build_theme_rows(grouped[:dark]  || [], current_slug)
          light_rows = build_theme_rows(grouped[:light] || [], current_slug)

          payload = {
            "body"     => Pito::Copy.render("pito.copy.theme.list_intro"),
            "sections" => [
              { title: I18n.t("pito.slash.theme.list.dark_header"),  rows: dark_rows },
              { title: I18n.t("pito.slash.theme.list.light_header"), rows: light_rows }
            ]
          }
          Pito::FollowUp.make_followupable!(payload, target: "theme_list", conversation: conversation)
          payload
        end

        # Build kv rows for a group of theme definitions. The current theme is
        # marked with a "this one" suffix in value2 (rendered in cyan, not dim).
        def build_theme_rows(definitions, current_slug)
          definitions.map do |d|
            row = { key: d.slug, value: d.label }
            row[:value2] = Pito::Copy.render("pito.copy.theme.current_marker") if d.slug == current_slug
            row
          end
        end
      end
    end
  end
end
