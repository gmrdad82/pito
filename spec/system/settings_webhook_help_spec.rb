require "rails_helper"

# Phase 26 — 01d. Critical journey: `[help]` link in the Slack pane on
# `/settings` opens the modal with the Slack guide rendered; same for
# Discord.
#
# We drive with `rack_test` rather than the JS-capable driver. The
# `[help]` link's `href` is the full Markdown-fragment URL
# (`/settings/webhooks/help/<provider>`); a rack_test click follows
# the href and lands on the rendered guide. The Stimulus controller
# (the JS-on path) is exercised separately by the request specs and
# unit-level confirmation that the controller registers on `<body>`.
#
# The full Capybara+JS path is intentionally NOT added here per the
# project's spec pyramid rule (system specs stay thin).
RSpec.describe "Settings webhook help", type: :system do
  before { driven_by(:rack_test) }

  describe "Slack [help] link" do
    it "navigates to the Slack guide fragment" do
      visit settings_path
      # rack_test resolves the `[help]` link's href even though Stimulus
      # would normally `preventDefault` and open the modal.
      within("[data-controller], body") do
        click_link("help", href: "/settings/webhooks/help/slack", match: :first)
      end
      expect(page).to have_current_path("/settings/webhooks/help/slack")
      expect(page).to have_content("Slack webhook setup")
      expect(page).to have_content("Create a Slack app")
      expect(page).to have_content("Add New Webhook to Workspace")
    end
  end

  describe "Discord [help] link" do
    it "navigates to the Discord guide fragment" do
      visit settings_path
      click_link("help", href: "/settings/webhooks/help/discord", match: :first)
      expect(page).to have_current_path("/settings/webhooks/help/discord")
      expect(page).to have_content("Discord webhook setup")
      expect(page).to have_content("Create a webhook")
      expect(page).to have_content("Copy Webhook URL")
    end
  end

  describe "modal scaffolding on /settings" do
    it "mounts the help modal dialog + Turbo Frame" do
      visit settings_path
      expect(page.body).to include('id="webhook-help-modal"')
      expect(page.body).to include('id="webhook_help_modal_frame"')
    end

    it "does NOT render data-turbo-confirm anywhere on /settings" do
      visit settings_path
      expect(page.body).not_to include("data-turbo-confirm")
    end
  end
end
