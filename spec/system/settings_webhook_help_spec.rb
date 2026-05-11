require "rails_helper"

# Phase 26 — 01d. Critical journey: the `[help]` link in the webhook
# panes resolves to the matching Markdown-fragment URL; the fragment
# renders the guide; the layout-level modal scaffolding is present so
# JS-on users get the modal flow.
#
# Driven by `rack_test`. The `[help]` link's `href` is the full
# Markdown-fragment URL (`/settings/webhooks/help/<provider>`); a
# rack_test click follows the href and lands on the rendered guide.
# The Stimulus controller (the JS-on path) is exercised by the
# request specs and confirmed by the modal-scaffold assertion below.
#
# The Slack + Discord panes themselves are partial-rendered (their
# integration into `/settings` is a separate 01g/01b/01c concern);
# this spec proves 01d's surface — help-link → rendered guide — in
# isolation.
RSpec.describe "Settings webhook help", type: :system do
  before { driven_by(:rack_test) }

  describe "Slack [help] link" do
    it "resolves to the Slack guide fragment URL" do
      visit settings_webhooks_help_path(provider: "slack")
      expect(page).to have_current_path("/settings/webhooks/help/slack")
      expect(page).to have_content("Slack webhook setup")
      expect(page).to have_content("Create a Slack app")
      expect(page).to have_content("Add New Webhook to Workspace")
    end
  end

  describe "Discord [help] link" do
    it "resolves to the Discord guide fragment URL" do
      visit settings_webhooks_help_path(provider: "discord")
      expect(page).to have_current_path("/settings/webhooks/help/discord")
      expect(page).to have_content("Discord webhook setup")
      expect(page).to have_content("Create a webhook")
      expect(page).to have_content("Copy Webhook URL")
    end
  end

  describe "modal scaffolding on /settings" do
    it "mounts the help modal dialog + Turbo Frame in the layout" do
      visit settings_path
      expect(page.body).to include('id="webhook-help-modal"')
      expect(page.body).to include('id="webhook_help_modal_frame"')
    end

    it "wires the webhook-help-modal Stimulus controller on <body>" do
      visit settings_path
      expect(page.body).to match(/<body[^>]*data-controller="[^"]*webhook-help-modal/)
    end

    it "does NOT render data-turbo-confirm anywhere on /settings" do
      visit settings_path
      expect(page.body).not_to include("data-turbo-confirm")
    end
  end

  describe "rendered guide fragment" do
    it "carries the matching turbo-frame id so Turbo can swap it in" do
      visit settings_webhooks_help_path(provider: "slack")
      expect(page.body).to include('id="webhook_help_modal_frame"')
    end

    it "renders Markdown server-side (no raw markdown leaks into the body)" do
      visit settings_webhooks_help_path(provider: "slack")
      # The h1 is rendered HTML, not `# Slack webhook setup` raw.
      expect(page.body).to include("<h1>Slack webhook setup</h1>")
      expect(page.body).not_to include("# Slack webhook setup")
    end

    it "renders code blocks for the webhook URL example" do
      visit settings_webhooks_help_path(provider: "slack")
      expect(page.body).to include("<pre>")
      expect(page.body).to include("hooks.slack.com")
    end

    it "renders the troubleshooting section" do
      visit settings_webhooks_help_path(provider: "slack")
      expect(page).to have_content("Troubleshooting")
    end

    it "404s on an unknown provider" do
      visit "/settings/webhooks/help/mars"
      expect(page.status_code).to eq(404)
    end
  end
end
