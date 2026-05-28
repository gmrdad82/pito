# frozen_string_literal: true

module Ui
  class PalettesController < ApplicationController
    allow_anonymous :show

    def show
      @slash_commands = [
        { verb: "authenticate", description: "Authenticate to access pito" },
        { verb: "channels",     description: "List your YouTube channels" },
        { verb: "videos",       description: "List videos for a channel" },
        { verb: "import",       description: "Import channel or video metadata" },
        { verb: "export",       description: "Export session transcript" },
        { verb: "help",         description: "Show help and command reference" },
        { verb: "clear",        description: "Clear the current session" },
        { verb: "new",          description: "Start a new session" }
      ]

      @ctrlp_sections = [
        {
          title: "Suggested",
          items: [
            { name: "New session",       shortcut: "ctrl+x n" },
            { name: "Switch session",    shortcut: "ctrl+x l" },
            { name: "Switch channel",    shortcut: "tab" },
            { name: "Switch period",     shortcut: "shift+tab" }
          ]
        },
        {
          title: "Session",
          items: [
            { name: "Open editor",            shortcut: "ctrl+x e" },
            { name: "Rename session",          shortcut: "ctrl+r" },
            { name: "Jump to message",         shortcut: "ctrl+x g" },
            { name: "Fork session" },
            { name: "Compact session",         shortcut: "ctrl+x c" },
            { name: "Share session" },
            { name: "Export transcript",       shortcut: "ctrl+x x" }
          ]
        },
        {
          title: "Channel",
          items: [
            { name: "Refresh channels" },
            { name: "Add channel" },
            { name: "Remove channel" },
            { name: "Toggle channel filter" }
          ]
        },
        {
          title: "Output",
          items: [
            { name: "Copy last assistant message",  shortcut: "ctrl+x y" },
            { name: "Copy session transcript" },
            { name: "Show tool details" },
            { name: "Toggle sidebar",               shortcut: "ctrl+x b" },
            { name: "Show timestamps" }
          ]
        }
      ]

      @slash_selected_index = 0
      @ctrlp_selected_section_index = 0
      @ctrlp_selected_item_index = 0
    end
  end
end
