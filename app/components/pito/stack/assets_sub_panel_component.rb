module Pito
  module Stack
    # Pito::Stack::AssetsSubPanelComponent
    #
    # Assets storage sub-panel inside the stack panel on Home.
    #
    # Shows: a hint line (`Assets writable` or `Assets not writable`) at
    # the top of the body, followed by per-category file count + size
    # breakdown (cover arts + composites). The title-row status chip was
    # removed (Phase 1D); status is now conveyed via the hint line.
    #
    # ## Kwargs
    #
    # @param storage_status [Hash] assets root probe — keys:
    #   `:path`, `:present`, `:writable`, `:size_bytes`,
    #   `:file_count`. Drives hint-line status word: `writable` (writable
    #   present), `not writable` (present but not writable or absent).
    # @param breakdown [Array<Hash>] per-category rows — `:label`,
    #   `:file_count` (nil → em-dash), `:size_bytes` (nil → em-dash).
    #
    # ## Cable channel
    #
    # `pito:home:stack:assets` — broadcasts assets breakdown updates.
    #
    # ## Focusables
    #
    # - `assets` (style: :inert) — a single inert focusable on the
    #   sub-panel root so the cursor can LAND on the Assets sub-panel
    #   during h/l traversal across the Stack panel. No action fires on
    #   Enter/Space; the focusable gives the cursor a stop in the flat
    #   focusables list so `syncSubPanelFromFocusable` snaps the visible
    #   sub-panel border accent to Assets. Without this stop, h/l would
    #   skip Assets entirely (it has no `[reindex]` / action to focus).
    #   FB-187 (2026-05-23).
    # - `assets_header` (style: :inert) — header row focusable on the
    #   breakdown table so j/k can land ON the sortable header. The
    #   stop gives `s` / `S` a sub-panel-scoped focus context. Emitted
    #   only when the breakdown table is rendered (non-empty).
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `SortableHeaderComponent` (sortable column headers)
    class AssetsSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:assets".freeze

      def initialize(storage_status:, breakdown:, current_sort: "files", current_dir: "desc")
        @storage_status = storage_status
        @breakdown = breakdown
        @current_sort = current_sort
        @current_dir  = current_dir
      end

      attr_reader :storage_status, :breakdown, :current_sort, :current_dir

      # Returns a single inert focusable on the sub-panel root so the
      # cursor lands on Assets during h/l traversal across the Stack
      # panel's 2x2 sub-panel grid. Inert = no Enter/Space action fires.
      def focusables
        list = [ { key: "assets", style: :inert } ]
        list << { key: "assets_header", style: :inert } if breakdown.any?
        list
      end

      def state
        if storage_status[:present]
          storage_status[:writable] ? :writable : :read_only
        else
          :absent
        end
      end

      # Normalizes `state` to an i18n status key.
      # `:writable` → `"writable"`; `:read_only` / `:absent` → `"not_writable"`.
      def hint_state_key
        state == :writable ? "writable" : "not_writable"
      end

      # Full i18n'd hint line string for the sub-panel body top.
      # E.g. "Assets writable" or "Assets not writable".
      # Sourced from `tui.stack.hint.assets` + `tui.stack.status.*`
      # so the future Rust TUI client reads the same YAML.
      def hint_text
        I18n.t(
          "tui.stack.hint.assets",
          status: I18n.t("tui.stack.status.#{hint_state_key}"),
        )
      end

      # CSS modifier class for the ENTIRE hint line.
      # Writable → green (is-success); not writable → red (is-danger).
      def hint_color_class
        state == :writable ? "is-success" : "is-danger"
      end

      # Phase 1C (2026-05-24) — `:` palette commands for this sub-panel.
      # Sort by category / files / size + sync toggle. Assets has no
      # reindex action. See `Pito::CommandPalette::Collector` for the
      # merge contract.
      def panel_commands
        [
          { key: "sort_assets_category",
            name: I18n.t("tui.commands.sort_table_category.name"),
            hint: I18n.t("tui.commands.sort_table_category.hint"),
            action_name: :sort_table,
            args: { table: "stack-assets", column: 0 } },
          { key: "sort_assets_files",
            name: I18n.t("tui.commands.sort_table_files.name"),
            hint: I18n.t("tui.commands.sort_table_files.hint"),
            action_name: :sort_table,
            args: { table: "stack-assets", column: 1 } },
          { key: "sort_assets_size",
            name: I18n.t("tui.commands.sort_table_size.name"),
            hint: I18n.t("tui.commands.sort_table_size.hint"),
            action_name: :sort_table,
            args: { table: "stack-assets", column: 2 } },
          { key: "sync_toggle_assets",
            name: I18n.t("tui.commands.sync_toggle.name", label: "assets"),
            hint: I18n.t("tui.commands.sync_toggle.hint", label: "assets"),
            action_name: :sync_toggle,
            args: { target: "home.stack.assets" } }
        ]
      end
    end
  end
end
