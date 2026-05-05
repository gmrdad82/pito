# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "chartkick", to: "chartkick.js"
pin "Chart.bundle", to: "Chart.bundle.js"

# Phase B post-commit (2026-05-04) — Note revamp.
# `marked` powers live client-side markdown rendering in the note editor's
# preview pane (no SSR round-trip on input). It does NOT sanitize by
# default — `dompurify` runs over the rendered HTML before injection.
# Pinned via jsDelivr ESM bundles for importmap compatibility.
pin "marked", to: "https://cdn.jsdelivr.net/npm/marked@15.0.7/lib/marked.esm.js"
pin "dompurify", to: "https://cdn.jsdelivr.net/npm/dompurify@3.2.4/dist/purify.es.mjs"
