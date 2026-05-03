require "rails_helper"

# Smoke tests for the Cloudflare-tunneled hostnames (app.pitomd.com and
# mcp.pitomd.com). The tunnel forwards public requests to localhost:3000
# (web) and localhost:3001 (MCP); Rails sees the public Host header.
#
# These specs exercise development-time host authorization and the
# canonical default_url_options hookup. They run in test env, where
# config.hosts is permissive by default, so they're more about asserting
# the wiring (URL helpers honour the canonical host) and that the JSON
# endpoints return 200 with a Cloudflare-style Host header.
RSpec.describe "Cloudflare-tunneled hostnames", type: :request do
  describe "JSON endpoints accept Host: app.pitomd.com" do
    it "returns 200 for /dashboard.json" do
      get "/dashboard.json", headers: { "HOST" => "app.pitomd.com" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "returns 200 for /channels.json" do
      get "/channels.json", headers: { "HOST" => "app.pitomd.com" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "returns 200 for /settings.json" do
      get "/settings.json", headers: { "HOST" => "app.pitomd.com" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end
  end

  describe "default_url_options wiring (development env contract)" do
    it "pins the development default URL options to app.pitomd.com over https" do
      # Boot the development environment in isolation and read the wired
      # default_url_options. We can't switch Rails.env mid-suite, so simulate
      # by reading the development.rb source — the spec is a guard against
      # accidental rollback of the canonical host.
      dev_config = Rails.root.join("config/environments/development.rb").read

      expect(dev_config).to include('host: "app.pitomd.com"')
      expect(dev_config).to include('protocol: "https"')
      expect(dev_config).to include('config.hosts << "app.pitomd.com"')
      expect(dev_config).to include('config.hosts << "mcp.pitomd.com"')
    end

    it "pins ActionCable allowed origins to include the public host" do
      dev_config = Rails.root.join("config/environments/development.rb").read

      expect(dev_config).to include('"https://app.pitomd.com"')
      expect(dev_config).to include('"https://mcp.pitomd.com"')
      expect(dev_config).to match(/allowed_request_origins\s*=/)
    end
  end
end
