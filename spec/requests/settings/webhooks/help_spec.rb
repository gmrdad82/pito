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

  # Phase 26 — 01d. The help guides render through
  # `ApplicationHelper#render_markdown(plain: true)`. `plain: true`
  # turns off Commonmarker's default header-anchor and syntax-
  # highlighter plugins so the modal styling can lay out the guide
  # with its own monospace typography. These specs lock that surface
  # in so a future tweak to `render_markdown` defaults can't bleed
  # the styled chrome into the help modal.
  describe "Markdown rendering posture" do
    it "renders headings without injected anchor links" do
      get settings_webhooks_help_path(provider: "slack")
      # The styled render path emits
      # `<h1><a href="#…" class="anchor" …></a>Slack webhook setup</h1>`.
      # The plain path emits `<h1>Slack webhook setup</h1>`.
      expect(response.body).not_to include('class="anchor"')
      expect(response.body).not_to match(/<h1><a [^>]*aria-hidden/)
    end

    it "renders code blocks without inline syntax-highlight styling" do
      get settings_webhooks_help_path(provider: "slack")
      # The styled render path emits `<pre style="background-color:…">`.
      # The plain path emits `<pre>` (and `<pre lang="…">` for fenced
      # blocks with a language tag; the guides use indented blocks
      # which produce bare `<pre>`).
      expect(response.body).not_to include("background-color:#2b303b")
      expect(response.body).not_to match(/<pre[^>]*style=/)
    end
  end

  describe "Troubleshooting section" do
    it "renders the Slack troubleshooting heading + key error paths" do
      get settings_webhooks_help_path(provider: "slack")
      expect(response.body).to include("Troubleshooting")
      expect(response.body).to include("webhook URL is invalid")
      expect(response.body).to include("test ping failed")
    end

    it "renders the Discord troubleshooting heading + key error paths" do
      get settings_webhooks_help_path(provider: "discord")
      expect(response.body).to include("Troubleshooting")
      expect(response.body).to include("webhook URL is invalid")
      expect(response.body).to include("test ping failed")
      expect(response.body).to include("Manage Webhooks")
    end
  end

  # Phase 26 — 01d (polish 2026-05-11). User feedback called out the
  # original guide layout as hard to follow: horizontal scroll from
  # long webhook URLs in code blocks, dense paragraphs with no visual
  # rhythm between steps, troubleshooting written as a wall of bold
  # paragraphs. The restructure introduces three signals the specs
  # below lock in:
  #   - `<hr>` separators between major sections
  #   - GFM tables in the Troubleshooting / Notifications behavior /
  #     in-step field-description sections
  #   - explicit horizontal rules before every Step heading
  describe "rendered structure polish" do
    %w[slack discord].each do |provider|
      it "renders horizontal rules between sections of the #{provider} guide" do
        get settings_webhooks_help_path(provider: provider)
        # Each guide has 5+ `---` separators between sections.
        expect(response.body.scan(/<hr\s*\/?>/).size).to be >= 4
      end

      it "renders the #{provider} troubleshooting matrix as a table" do
        get settings_webhooks_help_path(provider: provider)
        expect(response.body).to include("<table>")
        expect(response.body).to include("<th>")
        expect(response.body).to include("Error message")
        expect(response.body).to include("What it means")
        expect(response.body).to include("What to do")
      end

      it "renders the #{provider} notifications-behavior block as a table" do
        get settings_webhooks_help_path(provider: provider)
        # Both guides carry a `| Checkbox | What it does |` table.
        expect(response.body).to include("<th>Checkbox</th>")
        expect(response.body).to include("<th>What it does</th>")
        expect(response.body).to include("deliver every notification")
      end

      it "preserves proper-noun capitalization in the #{provider} guide" do
        get settings_webhooks_help_path(provider: provider)
        # Discord / Slack / YouTube / Pito stay capitalized at the
        # start of sentences and in their canonical brand form.
        expect(response.body).to include(provider.capitalize)
      end
    end
  end
end
