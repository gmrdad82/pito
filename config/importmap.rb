# Pin vendored modules
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@rails/actioncable", to: "actioncable.js"
pin "application", to: "application.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "pito/auth", to: "pito/auth.js"
pin "pito/settings", to: "pito/settings.js"
pin "pito/turbo_actions", to: "pito/turbo_actions.js"
pin "pito/ready", to: "pito/ready.js"
