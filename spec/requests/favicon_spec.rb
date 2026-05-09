require "rails_helper"

# Phase 7.5 — MCP custom-connector icon discovery.
#
# Some clients and OS-level icon scrapers ONLY check `/favicon.ico`.
# Pito does NOT carry a `.ico` binary in the repo — `public/Pito.png`
# is the brand mark and the single source of truth. A 301 redirect
# from `/favicon.ico` → `/Pito.png` is enough for any client that
# follows redirects (which is everything modern). See
# `config/routes.rb` for the route declaration. `ActionDispatch::Static`
# serves files from `public/` ahead of the router, so the route only
# fires when no `public/favicon.ico` file exists (the steady state).
RSpec.describe "/favicon.ico redirect", type: :request, unauthenticated: true do
  it "redirects /favicon.ico to /Pito.png with a 301" do
    get "/favicon.ico"

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/Pito.png")
  end

  it "is reachable without authentication" do
    # Plain `redirect(...)` is mounted at the routes layer, ahead of
    # any controller-level auth chain. Mirror the well-known specs'
    # anonymous-access assertion for completeness.
    get "/favicon.ico"
    expect(response).to have_http_status(:moved_permanently)
  end
end
