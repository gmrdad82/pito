module Tui
  # FB-170 (2026-05-21) — V6 `:command` palette ViewComponent.
  #
  # Renders the palette shell — vim-line input at viewport bottom +
  # inline suggestion list flush above the line. Hidden by default;
  # toggled by the `tui-command-palette` Stimulus controller which
  # listens for `:` in NORMAL mode and opens the palette.
  #
  # V6 contract (locked from `tmp/demo-command-palette.html`):
  #   - Vim-line at the bottom of `<main>`, anchored ABOVE the BST.
  #   - Inline suggestion list (NOT a popover) above the line.
  #   - Esc closes; Tab cycles next; Shift-Tab cycles previous; Enter
  #     runs the selected command; Backspace edits the input.
  #
  # The commands list is serialized into the root element's
  # `data-tui-command-palette-commands-value` attribute as JSON so the
  # Stimulus controller can filter / select / execute without a server
  # round-trip per keystroke. Each command's `path:` Proc is resolved
  # to a String at render time (commands without a `path:` carry an
  # explicit `action:` instead).
  class CommandPaletteComponent < ViewComponent::Base
    def initialize(commands:)
      @commands = Array(commands)
    end

    attr_reader :commands

    # Serialize the commands to a JSON-safe array of hashes. The Proc
    # in `path:` is invoked here so the wire format contains plain
    # strings (Stimulus can't call back into Ruby).
    def commands_json
      commands.map { |c| serialize(c) }.to_json
    end

    private

    def serialize(command)
      out = {
        name: command[:name].to_s,
        hint: command[:hint].to_s
      }
      if command[:path].respond_to?(:call)
        out[:path] = safe_call(command[:path])
      elsif command[:path].is_a?(String)
        out[:path] = command[:path]
      end
      out[:method] = command[:method].to_s if command[:method]
      out[:action] = command[:action].to_s if command[:action]
      out[:target] = command[:target] if command[:target]
      # ADR 0018 — Action bus. Commands carrying an `action_name` get
      # dispatched through `window.Pito.dispatchAction` in the JS
      # controller (`tui_command_palette_controller.js#run`). The key
      # is serialized as a String so the JSON registry lookup
      # (`pito_actions.js#dispatchAction`) finds the matching entry.
      out[:action_name] = command[:action_name].to_s if command[:action_name]
      out
    end

    def safe_call(proc)
      proc.call
    rescue StandardError
      # Routes may not be loadable in every render context (specs that
      # render the component in isolation). Fall back to a stable
      # sentinel so the wire format stays valid JSON; the JS controller
      # treats "" as a no-op navigation.
      ""
    end
  end
end
