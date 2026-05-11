require "rails_helper"

# Phase 26 — 01d. Help-modal Markdown guides for the Slack + Discord
# webhook panes.
#
# Endpoint: `GET /settings/webhooks/help/:provider`. The matching
# `[help]` link in each Settings pane targets this URL via a Turbo
# Frame; the response is a `layout: false` fragment rendered into the
# layout-level help modal. Direct browser navigation also returns
# usable HTML (the guide rendered as-is) so JS-off users still land on
# something readable.
RSpec.describe "Settings::Webhooks::Help", type: :request do
  describe "GET /settings/webhooks/help/slack" do
    it "returns 200" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response).to have_http_status(:ok)
    end

    it "renders the Slack heading from the Markdown guide" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include("<h1>Slack webhook setup</h1>")
    end

    it "renders the four step headings from the Slack guide" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include("Step 1")
      expect(response.body).to include("Create a Slack app")
      expect(response.body).to include("Step 2")
      expect(response.body).to include("Enable Incoming Webhooks")
      expect(response.body).to include("Step 3")
      expect(response.body).to include("Add a webhook URL to a channel")
      expect(response.body).to include("Step 4")
      expect(response.body).to include("Paste into Pito")
    end

    it "mentions the key UI strings beginners need to find" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include("Create New App")
      expect(response.body).to include("From scratch")
      expect(response.body).to include("Add New Webhook to Workspace")
      expect(response.body).to include("Incoming Webhooks")
    end

    it "includes the notifications behavior section" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include("Notifications behavior")
      expect(response.body).to include("deliver every notification")
      expect(response.body).to include("daily digest")
    end

    it "wraps the rendered guide in the help-modal Turbo Frame" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include('id="webhook_help_modal_frame"')
    end

    it "is reachable without the application chrome (layout: false)" do
      # The fragment renders without the chrome — no navbar, no
      # footer, no `<body data-controller="keyboard …">`.
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).not_to include('data-controller="keyboard')
    end

    it "renders without JS `confirm`/`alert`/`prompt` hooks" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).not_to include("data-turbo-confirm")
      expect(response.body).not_to match(/window\.confirm/)
      expect(response.body).not_to match(/window\.alert/)
    end
  end

  describe "GET /settings/webhooks/help/discord" do
    it "returns 200" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response).to have_http_status(:ok)
    end

    it "renders the Discord heading from the Markdown guide" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response.body).to include("<h1>Discord webhook setup</h1>")
    end

    it "renders the three step headings from the Discord guide" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response.body).to include("Step 1")
      expect(response.body).to include("Open the channel settings")
      expect(response.body).to include("Step 2")
      expect(response.body).to include("Create a webhook")
      expect(response.body).to include("Step 3")
      expect(response.body).to include("Paste into Pito")
    end

    it "mentions the key UI strings beginners need to find" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response.body).to include("Channel Settings")
      expect(response.body).to include("Integrations")
      expect(response.body).to include("New Webhook")
      expect(response.body).to include("Copy Webhook URL")
    end

    it "wraps the rendered guide in the help-modal Turbo Frame" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response.body).to include('id="webhook_help_modal_frame"')
    end
  end

  describe "invalid providers" do
    # The router constraint pins `:provider` to `/slack|discord/`, so a
    # request to any other provider is rejected by routing itself with
    # a `ActionController::RoutingError` (which Rails surfaces as 404
    # in production). Use a plain `get` against the raw URL to bypass
    # the named-route helper.
    it "404s on an unknown provider" do
      get "/settings/webhooks/help/mars"
      expect(response).to have_http_status(:not_found)
    end

    it "404s on an empty provider segment" do
      get "/settings/webhooks/help/"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authentication" do
    it "redirects unauthenticated callers to /login", :unauthenticated do
      get settings_webhooks_help_path(provider: "slack")
      expect(response).to redirect_to(login_path)
    end
  end
end
