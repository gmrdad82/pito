# frozen_string_literal: true

module Ui
  class PalettesController < ApplicationController
    allow_anonymous :show

    def show
      @slash_commands = [
        { verb: "authenticate", description_key: "pito.palette.slash.descriptions.authenticate" },
        { verb: "channels",     description_key: "pito.palette.slash.descriptions.channels" },
        { verb: "videos",       description_key: "pito.palette.slash.descriptions.videos" },
        { verb: "import",       description_key: "pito.palette.slash.descriptions.import" },
        { verb: "export",       description_key: "pito.palette.slash.descriptions.export" },
        { verb: "help",         description_key: "pito.palette.slash.descriptions.help" },
        { verb: "clear",        description_key: "pito.palette.slash.descriptions.clear" },
        { verb: "new",          description_key: "pito.palette.slash.descriptions.new" }
      ]

      @ctrlp_sections = [
        {
          title_key: "pito.palette.ctrl_p.sections.suggested",
          items: [
            { label_key: "pito.palette.ctrl_p.commands.new_session",       shortcut: "ctrl+x n" },
            { label_key: "pito.palette.ctrl_p.commands.switch_session",    shortcut: "ctrl+x l" },
            { label_key: "pito.palette.ctrl_p.commands.switch_channel",    shortcut: "tab" },
            { label_key: "pito.palette.ctrl_p.commands.switch_period",     shortcut: "shift+tab" }
          ]
        },
        {
          title_key: "pito.palette.ctrl_p.sections.session",
          items: [
            { label_key: "pito.palette.ctrl_p.commands.open_editor",            shortcut: "ctrl+x e" },
            { label_key: "pito.palette.ctrl_p.commands.rename_session",          shortcut: "ctrl+r" },
            { label_key: "pito.palette.ctrl_p.commands.jump_to_message",         shortcut: "ctrl+x g" },
            { label_key: "pito.palette.ctrl_p.commands.fork_session" },
            { label_key: "pito.palette.ctrl_p.commands.compact_session",         shortcut: "ctrl+x c" },
            { label_key: "pito.palette.ctrl_p.commands.share_session" },
            { label_key: "pito.palette.ctrl_p.commands.export_transcript",       shortcut: "ctrl+x x" }
          ]
        },
        {
          title_key: "pito.palette.ctrl_p.sections.channel",
          items: [
            { label_key: "pito.palette.ctrl_p.commands.refresh_channels" },
            { label_key: "pito.palette.ctrl_p.commands.add_channel" },
            { label_key: "pito.palette.ctrl_p.commands.remove_channel" },
            { label_key: "pito.palette.ctrl_p.commands.toggle_channel_filter" }
          ]
        },
        {
          title_key: "pito.palette.ctrl_p.sections.output",
          items: [
            { label_key: "pito.palette.ctrl_p.commands.copy_last_assistant_message",  shortcut: "ctrl+x y" },
            { label_key: "pito.palette.ctrl_p.commands.copy_session_transcript" },
            { label_key: "pito.palette.ctrl_p.commands.show_tool_details" },
            { label_key: "pito.palette.ctrl_p.commands.toggle_sidebar",               shortcut: "ctrl+x b" },
            { label_key: "pito.palette.ctrl_p.commands.show_timestamps" }
          ]
        }
      ]

      @slash_selected_index = 0
      @ctrlp_selected_section_index = 0
      @ctrlp_selected_item_index = 0
    end
  end
end
