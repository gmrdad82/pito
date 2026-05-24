module Pito
  module CommandPalette
    # Phase 1C (2026-05-24) — section-specific `:` command palette merge.
    #
    # Builds the per-scope command catalog the `:` palette displays when
    # the user opens it. Three scopes stack from most-specific to
    # least-specific:
    #
    #   1. focused sub-panel commands (if any)
    #   2. focused panel commands
    #   3. screen-level + global commands (from `Tui::CommandRegistry`)
    #
    # The collector is the canonical merger used BOTH by Ruby specs
    # (deterministic shape assertions) AND by the JS palette controller
    # (which scans the DOM for `data-panel-commands` attrs at open time
    # and concatenates them in the same order). Keeping the merge logic
    # here means a Ratatui TUI sibling can call the same merge through a
    # shared rake-exported screen spec — no behavioral drift between web
    # and TUI palettes.
    #
    # ## Command hash shape
    #
    # Every command hash carries:
    #
    #   key:         String  — stable identifier (used for tests + JS de-dup)
    #   name:        String  — user-typed verb shown in the suggestion list
    #   hint:        String  — short description rendered to the right
    #   action_name: Symbol  — entry in `Pito::ActionRegistry` (dispatched
    #                          through `window.Pito.dispatchAction`)
    #   args:        Hash    — optional payload merged into the action call
    #   scope:       Symbol  — `:sub_panel`, `:panel`, or `:screen`
    #
    # ## Inputs
    #
    # @param panel_commands     [Array<Hash>] from focused panel VC
    # @param sub_panel_commands [Array<Hash>] from focused sub-panel VC (or [])
    # @param screen_commands    [Array<Hash>] from `Tui::CommandRegistry`
    #   (the existing global + screen-scoped catalog)
    #
    # ## Output
    #
    # Flat `Array<Hash>` in the order above. Each entry annotated with
    # its `scope:` so the JS controller (and specs) can group / filter.
    class Collector
      class << self
        def call(panel_commands: [], sub_panel_commands: [], screen_commands: [])
          merged = []
          Array(sub_panel_commands).each { |c| merged << annotate(c, :sub_panel) }
          Array(panel_commands).each     { |c| merged << annotate(c, :panel) }
          Array(screen_commands).each    { |c| merged << annotate(c, :screen) }
          merged
        end

        private

        def annotate(command, scope)
          # Preserve any explicit `scope:` declared by the VC (each VC
          # MAY pre-tag a command, e.g. an aggregate `sync_toggle` that
          # lives on the panel but applies panel-wide). Default to the
          # collector-level scope otherwise.
          command.merge(scope: command[:scope] || scope)
        end
      end
    end
  end
end
