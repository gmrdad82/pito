module Pito
  module CommandPalette
    # Section-specific `:` command palette merge.
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
    # here means the web palette has one canonical ordering with no
    # behavioral drift between the Ruby and JS sides.
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
          dedupe(merged)
        end

        private

        def annotate(command, scope)
          # Preserve any explicit `scope:` declared by the VC (each VC
          # MAY pre-tag a command, e.g. an aggregate `sync_toggle` that
          # lives on the panel but applies panel-wide). Default to the
          # collector-level scope otherwise.
          command.merge(scope: command[:scope] || scope)
        end

        # 2026-05-24 — palette de-duplication.
        #
        # A command is "the same" iff it would dispatch identically: same
        # `action_name` AND same `args` payload (or same `path` when no
        # action_name). The first occurrence wins so the most-specific
        # scope (sub_panel > panel > screen) shadows any duplicate from a
        # broader scope. The unique `key` field is NOT used for
        # equivalence — by design two scopes may emit the same logical
        # action under different keys (e.g., `sync_toggle_stack` from the
        # panel + a generic `sync_toggle` from a screen catalog). We
        # collapse those into one row so the user never sees an exact
        # duplicate in the palette.
        def dedupe(commands)
          seen = {}
          commands.each_with_object([]) do |cmd, out|
            sig = signature_for(cmd)
            next if seen[sig]
            seen[sig] = true
            out << cmd
          end
        end

        def signature_for(cmd)
          if cmd[:action_name]
            [ :action, cmd[:action_name].to_sym, cmd[:args] || {} ]
          elsif cmd[:path]
            [ :path, cmd[:path], (cmd[:method] || :get).to_s.downcase ]
          else
            # Fall back to the key as the signature when neither
            # action_name nor path is present — keeps the entry but lets
            # the next occurrence dedupe.
            [ :key, cmd[:key] ]
          end
        end
      end
    end
  end
end
