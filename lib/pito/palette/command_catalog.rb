# frozen_string_literal: true

module Pito
  module Palette
    # Builds the grouped command list for the Ctrl+K palette.
    # Each section has a title_key and an array of items.
    # Each item carries:
    #   label_key  — i18n key displayed in the palette
    #   insert     — text pre-filled into the chatbox on Enter (may include <placeholders>)
    #   shortcut   — optional keyboard hint shown on the right (String or nil)
    class CommandCatalog
      def self.sections(authenticated: true)
        new.sections(authenticated:)
      end

      # Auth-gated, mirroring the slash typeahead: an unauthenticated visitor can
      # only `/login`, so the palette shows that single command — nothing else is
      # actionable until they authenticate.
      def sections(authenticated: true)
        unless authenticated
          return [ {
            title_key: "pito.palette.ctrl_k.sections.general",
            items:     [ login_item ]
          } ]
        end

        [
          {
            title_key: "pito.palette.ctrl_k.sections.youtube",
            items:     youtube_items
          },
          {
            title_key: "pito.palette.ctrl_k.sections.config",
            items:     config_items
          },
          {
            title_key: "pito.palette.ctrl_k.sections.conversations",
            items:     conversation_items
          },
          {
            title_key: "pito.palette.ctrl_k.sections.general",
            items:     general_items
          }
        ]
      end

      private

      def login_item
        { label_key: "pito.palette.ctrl_k.commands.login", insert: "/login <code>" }
      end

      def youtube_items
        [
          { label_key: "pito.palette.ctrl_k.commands.connect",
            insert:    "/connect" },
          { label_key: "pito.palette.ctrl_k.commands.disconnect",
            insert:    "/disconnect <@handle>" },
          { label_key: "pito.palette.ctrl_k.commands.search_games_for",
            insert:    "search games for " },
          { label_key: "pito.palette.ctrl_k.commands.search_games_like",
            insert:    "search games like " },
          { label_key: "pito.palette.ctrl_k.commands.search_games_about",
            insert:    "search games about " },
          { label_key: "pito.palette.ctrl_k.commands.search_vids_for",
            insert:    "search vids for " },
          { label_key: "pito.palette.ctrl_k.commands.search_vids_like",
            insert:    "search vids like " },
          { label_key: "pito.palette.ctrl_k.commands.search_vids_about",
            insert:    "search vids about " }
        ]
      end

      def config_items
        [
          { label_key: "pito.palette.ctrl_k.commands.config_ai",
            insert:    "/config ai" },
          { label_key: "pito.palette.ctrl_k.commands.config_google",
            insert:    "/config google" },
          { label_key: "pito.palette.ctrl_k.commands.config_igdb",
            insert:    "/config igdb" },
          { label_key: "pito.palette.ctrl_k.commands.config_webhook",
            insert:    "/config webhook" }
        ]
      end

      def conversation_items
        [
          { label_key: "pito.palette.ctrl_k.commands.new",    insert: "/new" },
          { label_key: "pito.palette.ctrl_k.commands.resume", insert: "/resume" },
          { label_key: "pito.palette.ctrl_k.commands.search_conversations_for",
            insert:    "search conversations for " },
          { label_key: "pito.palette.ctrl_k.commands.search_conversations_like",
            insert:    "search conversations like " }
        ]
      end

      # Authenticated general commands — no `/login` here (already signed in).
      def general_items
        [
          { label_key: "pito.palette.ctrl_k.commands.help",   insert: "/help" },
          { label_key: "pito.palette.ctrl_k.commands.logout", insert: "/logout" }
        ]
      end
    end
  end
end
