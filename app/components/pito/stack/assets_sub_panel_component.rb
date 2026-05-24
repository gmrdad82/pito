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

      def initialize(storage_status:, breakdown:)
        @storage_status = storage_status
        @breakdown = breakdown
      end

      attr_reader :storage_status, :breakdown

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
    end
  end
end
