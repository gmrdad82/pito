require "rails_helper"

# Phase 7.5 — MCP custom-connector icon discovery.
#
# `public/manifest.json` is a Web App Manifest that advertises the
# Pito brand icon (`/Pito.png`) and basic display metadata. It is one
# of the surfaces Claude.ai's MCP custom connector might probe to
# resolve a connector-list icon — there's no MCP spec for icons, so
# the layout `<head>` references it via `<link rel="manifest">` and
# Pito ships the file as a static asset under `public/` (served by
# `ActionDispatch::Static`).
#
# The spec is a smoke test: file resolves with 200 + valid JSON and
# the icons array points at the brand mark. Anonymous access — no
# auth chain involvement, since the manifest IS supposed to be
# public.
RSpec.describe "Web App Manifest", type: :request, unauthenticated: true do
  describe "GET /manifest.json" do
    it "returns valid JSON with the Pito icon" do
      get "/manifest.json"

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["name"]).to eq("pito")
      expect(body["short_name"]).to eq("pito")
      expect(body["description"]).to eq("best YouTube tool")
      expect(body["start_url"]).to eq("/")
      expect(body["display"]).to eq("standalone")

      icons = body["icons"]
      expect(icons).to be_an(Array)
      expect(icons).not_to be_empty
      expect(icons.first["src"]).to eq("/Pito.png")
      expect(icons.first["type"]).to eq("image/png")
    end

    it "is reachable without authentication" do
      # Mirrors `/.well-known/...` — the manifest is a public discovery
      # surface and must not redirect to /login.
      get "/manifest.json"
      expect(response).not_to be_redirect
      expect(response).to have_http_status(:ok)
    end
  end
end
