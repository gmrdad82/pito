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
end
