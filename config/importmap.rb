# Pin vendored modules
pin "@xterm/xterm", to: "xterm.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@rails/actioncable", to: "actioncable.js"
pin "application", to: "application.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
