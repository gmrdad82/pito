# ADR 0018 — Action bus + cable architecture.
#
# Boot-time registration of every user-triggerable action. Runs inside
# `after_initialize` so `Rails.application.routes.url_helpers` is
# resolvable (route loading happens AFTER initializer-load phase). Each
# `Pito::ActionRegistry.define` call wires one action into the canonical
# registry the JS dispatcher (`window.Pito.dispatchAction`) + Ruby
# dispatcher (`Pito::ActionDispatcher`) + future palette / leader menu /
# MCP / CLI consumers all read from.
#
# Initial migration scope (FB-178+180 / FB-126 / FB-171 spaghetti
# closeout): reindex_meilisearch + reindex_voyage. Subsequent actions
# (`update_slack_webhook`, `revoke_session`, etc.) folded in by their
# own dispatches per the ADR's migration plan.
Rails.application.config.after_initialize do
  routes = Rails.application.routes.url_helpers

  Pito::ActionRegistry.define(
    :reindex_meilisearch,
    path: -> { routes.settings_stack_meilisearch_reindex_path },
    method: :post,
    confirmation: { brand: "Meilisearch", danger: true },
    i18n_key: "tui.commands.reindex_meilisearch",
    cable_panel: "pito:settings:stack:meilisearch"
  )

  Pito::ActionRegistry.define(
    :reindex_voyage,
    path: -> { routes.settings_stack_voyage_reindex_path },
    method: :post,
    confirmation: { brand: "Voyage AI", danger: true },
    i18n_key: "tui.commands.reindex_voyage",
    cable_panel: "pito:settings:stack:voyage"
  )

  # Phase 1C (2026-05-24) — section-specific `:` palette actions.
  #
  # `sort_table` — programmatically clicks a `SortableHeaderComponent`
  # `<th>` inside a `[data-controller="sortable-table"]` block. The
  # palette command carries `args: { table: <id>, column: <n|name> }`;
  # the JS dispatcher (`pito_actions.js#dispatchAction`) reads them and
  # synthesizes a click on the right header. Pure client-side — no path,
  # no POST.
  #
  # `sync_toggle` — programmatically clicks the
  # `Tui::SyncIndicatorComponent` for the named target
  # (`home.stack.meilisearch`, `home.stack`, etc.). The args carry
  # `target: <name>`; the JS dispatcher finds the matching
  # `[data-sync-target=<name>]` element and `.click()`s it. Same wire
  # shape as sort_table — no path, no POST.
  #
  # `click_focusable` / `focus_focusable` — generic helpers the palette
  # uses for "press X" / "go to X" commands without a dedicated action.
  # JS finds `[data-tui-focusable=<key>]` and clicks / focuses.
  #
  # `revoke_all_except_current` / `revoke_selected_sessions` — STUB
  # entries; the underlying forms still POST through the legacy bulk-
  # revoke flow. Phase 2 lifts them into the action bus proper.
  Pito::ActionRegistry.define(
    :sort_table,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_table",
    cable_panel: nil
  )

  Pito::ActionRegistry.define(
    :sync_toggle,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sync_toggle",
    cable_panel: nil
  )

  Pito::ActionRegistry.define(
    :click_focusable,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.click_focusable",
    cable_panel: nil
  )

  Pito::ActionRegistry.define(
    :focus_focusable,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.focus_focusable",
    cable_panel: nil
  )

  Pito::ActionRegistry.define(
    :revoke_all_except_current,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.revoke_all_except_current",
    cable_panel: nil
  )

  Pito::ActionRegistry.define(
    :revoke_selected_sessions,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.revoke_selected_sessions",
    cable_panel: nil
  )
end
