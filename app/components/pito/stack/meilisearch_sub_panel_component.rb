module Pito
  module Stack
    # Pito::Stack::MeilisearchSubPanelComponent
    #
    # Meilisearch sub-panel inside the stack panel on Home.
    #
    # Shows: a hint line (`Meilisearch v<version> connected`) at the top
    # of the body, followed by `[reindex]` action + per-index stats
    # (games + bundles — doc count + size). The unified `games_<env>`
    # Meilisearch index is split into two rows by `kind` (`game` /
    # `bundle`); size is reported by Meilisearch at the INDEX level only,
    # so `omit_size` bundle row renders a plain dash in the size column.
    # The title-row status chip was removed (Phase 1D); status is now
    # conveyed via the hint line.
    #
    # FB-126 (2026-05-21) — `[reindex]` opens a
    # `Tui::ConfirmationDialogComponent` (mounted by the parent
    # `Pito::StackPanelComponent`) instead of POSTing directly.
    #
    # The idle + running children sit in the same DOM, toggled via
    # `hidden` so the action slot never collapses (no width jitter
    # when the swap fires).
    #
    # ## Kwargs
    #
    # @param healthy [Boolean] Meilisearch reachability
    # @param stats [Hash] aggregate Meilisearch stats — keys include
    #   `:version` (String or nil, from `MeilisearchEngine#version`).
    # @param per_index_stats [Array<Hash>] rows — `:label`,
    #   `:documents`, `:size_bytes`, `:missing` (bool — "not yet
    #   indexed"), `:omit_size` (bool — show dash for size).
    #
    # ## Cable channel
    #
    # `pito:home:stack:meilisearch` — broadcasts reindex state +
    # per-index stats updates.
    #
    # ## Focusables
    #
    # - `reindex_meilisearch` (style: :action) — only when reindex is
    #   NOT running. Resolved via
    #   `SettingsHelper#stack_reindex_focusables(running:)` which
    #   returns `[]` while running (the indicator slot is
    #   non-interactive).
    # - `meilisearch_header` (style: :inert) — header row focusable
    #   so j/k cycles can land ON the table header. Inert = no action
    #   fires on Enter/Space; the stop gives `s` / `S` a sub-panel-
    #   scoped focus context. Only emitted when `per_index_stats`
    #   is non-empty (no header row otherwise).
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `Tui::ActionButtonComponent` (`[reindex]` idle action)
    # - `Tui::ReindexProgressComponent` (`[=----]` running indicator)
    # - `SortableHeaderComponent` (sortable column headers)
    #
    # ## Top-border chrome contract (sub-panel-level) — LOCKED
    #
    # All four Stack sub-panels (`Meilisearch`, `Voyage`, `Postgres`,
    # `Assets`) share the same chrome contract described here. Sibling
    # sub-panel files reference this section as the canonical source.
    #
    # Every `.pito-sub-panel` is a rounded box (`border-radius: 10px`)
    # with a 1px solid border in `var(--color-border)`. The title and
    # optional action slots pierce the top border using real CSS borders
    # on the slot element — NOT pseudo-elements.
    #
    # ### Title slot
    #
    # The `.pito-sub-panel__title` element is positioned at:
    #
    #   top: -7px; left: 8px; height: 14px;
    #   border-left:  1px solid var(--color-border);
    #   border-right: 1px solid var(--color-border);
    #   padding: 0 6px;
    #   background: var(--section-bg, var(--color-bg));
    #
    # The background cuts through the sub-panel's top border so the
    # section-tinted page background shows through the notch.
    #
    # ### Action slot
    #
    # The top-right action slot (e.g. `[reindex]`) uses class
    # `.pito-sub-panel__actions`. Same chrome geometry: real
    # `border-left` + `border-right` + `padding: 0 6px` +
    # `background: var(--section-bg, var(--color-bg))`.
    #
    # ### Pipe contract — strict
    #
    # NEVER use `::before` / `::after` with `content: "│"` or
    # `content: ""` + background for the pipe brackets. The pipes are
    # CSS `border-left` / `border-right` on the slot element itself.
    # This was rejected in three separate polish rounds and is locked.
    #
    # ### Border radius
    #
    # `border-radius: 10px` on `.pito-sub-panel`. Locked — matches
    # `.pito-pane` and `.tui-dialog-frame`.
    class MeilisearchSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:meilisearch".freeze

      def initialize(healthy:, stats:, per_index_stats:)
        @healthy = healthy
        @stats = stats
        @per_index_stats = per_index_stats
      end

      attr_reader :healthy, :stats, :per_index_stats

      def reindex_running?
        AppSetting.reindex_running?
      end

      # FB-167 (2026-05-23) — inlined from `SettingsHelper#stack_reindex_focusables`
      # to remove the `helpers.*` call. ViewComponent raises
      # `HelpersCalledBeforeRenderError` when a parent component calls
      # `focusables` on a sub-panel that has NOT been rendered through
      # `render(...)` yet (the sub-panel is instantiated in Ruby for
      # focusable aggregation in `Pito::StackPanelComponent#focusable_keys`).
      # The original helper was pure logic — `running ? [] : [{...}]` —
      # so inlining is safe and matches the canonical-source rule.
      def focusables
        list = []
        list << { key: "reindex", style: :action } unless reindex_running?
        list << { key: "meilisearch_sync", style: :action }
        list << { key: "meilisearch_header", style: :inert } if per_index_stats.any?
        list
      end

      def state
        healthy ? :connected : :disconnected
      end

      # Version label string — e.g. "1.10.3". Falls back to "—" when the
      # engine is unreachable or the version probe returned nil.
      # Meilisearch convention uses a `v` prefix in user-facing copy
      # (e.g. "Meilisearch v1.10 connected"), so callers prepend "v"
      # in the template when the version is not "—".
      def meilisearch_version
        v = stats[:version].presence
        return "—" unless v

        # Trim to major.minor only (e.g. "1.10.3" → "1.10").
        parts = v.split(".")
        parts.first(2).join(".")
      end

      # Full i18n'd hint line string for the sub-panel body top.
      # E.g. "Meilisearch v1.10 connected" or "Meilisearch v— disconnected".
      # Sourced from `tui.stack.hint.meilisearch` + `tui.stack.status.*`
      # so the future Rust TUI client reads the same YAML.
      # Note: the i18n template includes the "v" prefix literal so the
      # em-dash fallback ("—") renders as "Meilisearch v— disconnected"
      # which the operator reads as "no version available".
      def hint_text
        I18n.t(
          "tui.stack.hint.meilisearch",
          version: meilisearch_version,
          status: I18n.t("tui.stack.status.#{state}"),
        )
      end

      # CSS modifier class for the ENTIRE hint line.
      # Connected → green (is-success); disconnected → red (is-danger).
      def hint_color_class
        healthy ? "is-success" : "is-danger"
      end
    end
  end
end
