# Pin npm packages by running ./bin/importmap

pin "application"
# ADR 0018 — Action bus. `pito_actions.js` sets `window.Pito` so every
# consumer (Stimulus controllers, palette, future leader menu, future
# MCP-web bridge) can call `Pito.dispatchAction(name)` without crafting
# its own POST flow. Pinned alongside `application` so importmap-rails
# serves the file under `/assets/`.
pin "pito_actions"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# 2026-05-18 (DR follow-up) — ActionCable JS for direct channel
# subscriptions (the `stack-stats-live` controller listens on
# `StackStatsChannel` for push-driven Stack-pane refreshes). The
# `actioncable` gem ships `actioncable.esm.js` as a static asset.
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "chartkick", to: "chartkick.js"
pin "Chart.bundle", to: "Chart.bundle.js"
