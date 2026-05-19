# frozen_string_literal: true

# Phase 7.5 connector hardening — Doorkeeper layout override.
#
# `app/views/doorkeeper/authorizations/{new,error}.html.erb` were
# restyled to Pito's design system (`:hide_chrome`, `max-width: 480px`,
# Pito monospace + design tokens). The view templates were correct, but
# the page rendered with Doorkeeper's bundled `doorkeeper/application`
# layout — `Doorkeeper::ApplicationController` defaults to
# `layout "doorkeeper/application"` because Rails resolves the layout
# from the controller's namespace. The result: serif heading,
# light-grey card, no Pito chrome.
#
# Fix: pin the HTML-rendering Doorkeeper controllers to Pito's
# `application` layout. Two controllers qualify:
#
#   - `Doorkeeper::AuthorizationsController` — renders the consent
#     screen (`new`) and the authorization error screen (`error`).
#   - `Doorkeeper::AuthorizedApplicationsController` — renders the
#     "applications you've authorized" admin index. We `skip_controllers
#     :authorized_applications` in routes.rb, so this controller never
#     mounts as a route, but pinning the layout is cheap insurance in
#     case a future routes change re-exposes it.
#
# `Doorkeeper::TokensController` and `Doorkeeper::TokenInfoController`
# inherit from `ApplicationMetalController` and never render HTML, so
# they don't need a layout override.
#
# The override runs inside `to_prepare` so it survives every code-reload
# pass in development (controllers get unloaded between requests).
Rails.application.config.to_prepare do
  controllers = []
  controllers << Doorkeeper::AuthorizationsController if defined?(Doorkeeper::AuthorizationsController)
  controllers << Doorkeeper::AuthorizedApplicationsController if defined?(Doorkeeper::AuthorizedApplicationsController)

  controllers.each do |controller|
    controller.layout "application"
  end
end
