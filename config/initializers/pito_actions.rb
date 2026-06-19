# ADR 0018 — Action bus + cable architecture.
#
# Boot-time registration of every user-triggerable action. Runs inside
# `after_initialize` so `Rails.application.routes.url_helpers` is
# resolvable (route loading happens AFTER initializer-load phase). Each
# `Pito::ActionRegistry.define` call wires one action into the canonical
# registry the JS dispatcher (`window.Pito.dispatchAction`) + Ruby
# dispatcher (`Pito::ActionDispatcher`) + future palette / leader menu /
# CLI consumers all read from.
#
# Initial migration scope (FB-178+180 / FB-126 / FB-171 spaghetti
# closeout): reindex_voyage. Subsequent actions
# (`update_slack_webhook`, `revoke_session`, etc.) folded in by their
# own dispatches per the ADR's migration plan.
Rails.application.config.after_initialize do
  routes = Rails.application.routes.url_helpers

  Pito::ActionRegistry.define(
    :reindex_voyage,
    path: -> { routes.settings_stack_voyage_reindex_path },
    method: :post,
    confirmation: { brand: "Voyage AI", danger: true },
    i18n_key: "tui.commands.reindex_voyage",
    cable_panel: "pito:settings:stack:voyage",
    scope: :home
  )

  # 2026-05-24 — section-specific `:` palette actions.
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
  # (`home.stack`, etc.). The args carry
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
  # revoke flow. A later iteration lifts them into the action bus proper.
  # scope: :global — these are palette-dispatch helpers used on every
  # screen. The JS dispatcher resolves them client-side (no Rails route,
  # no POST) so there is no screen-specific context requirement.
  Pito::ActionRegistry.define(
    :sort_table,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_table",
    cable_panel: nil,
    scope: :global
  )

  Pito::ActionRegistry.define(
    :sync_toggle,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sync_toggle",
    cable_panel: nil,
    scope: :global
  )

  Pito::ActionRegistry.define(
    :click_focusable,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.click_focusable",
    cable_panel: nil,
    scope: :global
  )

  Pito::ActionRegistry.define(
    :focus_focusable,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.focus_focusable",
    cable_panel: nil,
    scope: :global
  )

  # scope: :home — session revocation lives in the Security panel on the
  # home screen. These stubs must not surface on /videos or /games.
  Pito::ActionRegistry.define(
    :revoke_all_except_current,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.revoke_all_except_current",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :revoke_selected_sessions,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.revoke_selected_sessions",
    cable_panel: nil,
    scope: :home
  )

  # 2026-05-24 — `Space s` master TST sync toggle.
  #
  # Wired to the leader menu (`Tui::LeaderMenuComponent` DEFAULT_ENTRIES,
  # `s` entry). The JS dispatcher resolves the action by flipping the
  # `pito.sync.app` localStorage master switch (ONE global flag covers
  # every screen) and dispatching `tui:sync-changed` for the master
  # scope; every panel / sub-panel sync VC re-evaluates via the
  # existing cascade path (`isTargetSyncDisabled`). Per-panel user
  # preferences survive the global toggle via the per-panel "yes"
  # opt-in override.
  # scope: :global — master TST sync toggle applies on every screen.
  Pito::ActionRegistry.define(
    :toggle_tst_sync,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.toggle_tst_sync",
    cable_panel: nil,
    scope: :global
  )

  # 2026-05-25 — Pito::Calendar::MonthGridComponent navigation actions.
  #
  # Four GET actions drive Turbo Frame navigation in the home calendar panel.
  # All are scoped to :home (calendar nav only applies on the home screen).
  # The `month` arg is threaded through as `?month=YYYY-MM` in the JS
  # dispatcher payload — the controller reads it from `params[:month]`.
  #
  # `path` resolves the named-route helper minted by the
  # `namespace :pito { scope :calendar { ... } }` block in routes.rb.
  Pito::ActionRegistry.define(
    :calendar_prev_month,
    path: -> { routes.pito_calendar_prev_month_path },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.calendar_prev_month",
    cable_panel: "pito:home:calendar",
    scope: :home
  )

  Pito::ActionRegistry.define(
    :calendar_next_month,
    path: -> { routes.pito_calendar_next_month_path },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.calendar_next_month",
    cable_panel: "pito:home:calendar",
    scope: :home
  )

  Pito::ActionRegistry.define(
    :calendar_today,
    path: -> { routes.pito_calendar_today_path },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.calendar_today",
    cable_panel: "pito:home:calendar",
    scope: :home
  )

  Pito::ActionRegistry.define(
    :calendar_pick_year,
    path: -> { routes.pito_calendar_pick_year_path },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.calendar_pick_year",
    cable_panel: "pito:home:calendar",
    scope: :home
  )

  # `:calendar_filter_category` — redirects to / with `?calendar_category=<cat>|""`.
  # The JS dispatcher sends `args: { category: "channel"|"game"|"system"|"manual"|"" }`.
  # scope: :home — calendar is a home-screen panel only.
  Pito::ActionRegistry.define(
    :calendar_filter_category,
    path: -> { routes.pito_calendar_filter_category_path },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.calendar_filter_category",
    cable_panel: "pito:home:calendar",
    scope: :home
  )

  # 2026-05-25 — notifications feed panel palette commands (clean slate).
  #
  # `:notifications_feed_mark_read` — POSTs to `/notifications_feed/mark_read`
  # to mark every unread notification as read (no selection required).
  #
  # `:notifications_feed_mark_unread` — POSTs to `/notifications_feed/mark_unread`
  # to mark every read notification as unread (no selection required).
  #
  # scope: :home — notifications feed is a home-screen panel only.
  Pito::ActionRegistry.define(
    :notifications_feed_mark_read,
    path: -> { routes.mark_read_notifications_feed_index_path },
    method: :post,
    confirmation: nil,
    i18n_key: "tui.commands.notifications_feed_mark_read",
    cable_panel: "pito:home:notifications_feed",
    scope: :home
  )

  Pito::ActionRegistry.define(
    :notifications_feed_mark_unread,
    path: -> { routes.mark_unread_notifications_feed_index_path },
    method: :post,
    confirmation: nil,
    i18n_key: "tui.commands.notifications_feed_mark_unread",
    cable_panel: "pito:home:notifications_feed",
    scope: :home
  )

  # E1 (2026-05-25) — notifications settings panel palette commands.
  #
  # `toggle_all` / `toggle_daily_digest` — client-side click on the
  # matching checkbox focusable. Pure client-side stubs; no path / POST.
  # `focus_slack_webhook` / `focus_discord_webhook` — move keyboard focus
  # to the respective webhook URL input in the Notifications settings panel.
  # `open_slack_help_dialog` / `open_discord_help_dialog` — open the
  # per-brand webhook help dialog via the existing dialog opener flow.
  #
  # scope: :home — notifications settings is a home-screen panel only.
  Pito::ActionRegistry.define(
    :toggle_all,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.toggle_all",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :toggle_daily_digest,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.toggle_daily_digest",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :focus_slack_webhook,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.focus_slack_webhook",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :focus_discord_webhook,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.focus_discord_webhook",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :open_slack_help_dialog,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.open_slack_help_dialog",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :open_discord_help_dialog,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.open_discord_help_dialog",
    cable_panel: nil,
    scope: :home
  )

  # E1 (2026-05-25) — security panel palette commands (session table).
  #
  # Five sort commands + select_all are pure client-side sort/click
  # stubs that the JS dispatcher resolves via `sort_table` or
  # `click_focusable` dispatches. Named entries here surface human-
  # readable palette rows (e.g., "sort by device") so the user doesn't
  # need to type the generic "sort" command. Path "#" = client-side only.
  #
  # scope: :home — security / session management is a home-screen panel.
  Pito::ActionRegistry.define(
    :sort_sessions_device,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_sessions_device",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :sort_sessions_browser,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_sessions_browser",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :sort_sessions_ip,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_sessions_ip",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :sort_sessions_last_seen,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_sessions_last_seen",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :sort_sessions_created,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.sort_sessions_created",
    cable_panel: nil,
    scope: :home
  )

  Pito::ActionRegistry.define(
    :select_all_sessions,
    path: -> { "#" },
    method: :get,
    confirmation: nil,
    i18n_key: "tui.commands.select_all_sessions",
    cable_panel: nil,
    scope: :home
  )
end
