require "rails_helper"

# Phase 29 — Unit A1. System-level regression for the Settings
# integrations section after the AppSetting → credentials
# consolidation:
#
#   * The Slack + Discord webhook panes still render and still save
#     exactly as before (URL field + "every notification" /
#     "daily digest" checkboxes + `[update]` + the "... webhook updated."
#     confirmation). The storage layer was already correct — Unit A1
#     only changed the orphaned `AppSetting.*_enabled` gate behind it.
#   * The YouTube credentials pane is GONE (deploy-time credentials
#     config now).
#   * The Voyage.ai pane is slimmed — no API key field, just the
#     project-notes indexing toggle.
#
# Driven by `rack_test` — the panes are plain forms, no JS needed for
# the submit path. The Slack / Discord test ping is stubbed at the
# HTTP boundary.
#
# 2026-05-16 — recent-TOTP gate dropped from the webhook surfaces.
# Saves are plain saves now — no `totp_code` injection needed.
RSpec.describe "Settings integrations panes (Unit A1)", type: :system do
  before { driven_by(:rack_test) }

  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

  describe "the Slack pane" do
    it "renders the webhook URL field and the routing checkboxes" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Slack']]") do
        expect(page).to have_field("slack_webhook_url")
        expect(page).to have_field("everything", type: "checkbox")
        expect(page).to have_field("daily_digest", type: "checkbox")
        expect(page).to have_button("[update]")
      end
    end

    it "saves a webhook URL and shows the saved confirmation" do
      stub_request(:post, slack_url).to_return(status: 200, body: "ok")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='slack_webhook_url']]")
      within(form) do
        fill_in "slack_webhook_url", with: slack_url
        check "everything"
        click_button "[update]"
      end
      expect(page).to have_content("Slack webhook updated.")
      expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(slack_url)
    end

    # 2026-05-16 webhook-clear UX tweak.
    # The first checkbox label dropped its "deliver " prefix — the
    # word was redundant against the surrounding pane copy and the
    # `[update]` button. The bare "every notification" reads as a
    # routing toggle, matching the sibling "daily digest" label.
    it "renders the `every notification` label (not the old `deliver every notification`)" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Slack']]") do
        expect(page).to have_text("every notification")
        expect(page).not_to have_text("deliver every notification")
        expect(page).to have_text("daily digest")
      end
    end

    # 2026-05-16 webhook-clear UX tweak.
    # Clearing the URL field and hitting `[update]` persists the row
    # with nil URL + both flags off and surfaces the distinct
    # "Slack webhook cleared." flash.
    it "clears the integration on a blank URL submit" do
      NotificationDeliveryChannel.create!(
        kind: "slack", webhook_url: slack_url,
        everything: true, daily_digest: true
      )
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='slack_webhook_url']]")
      within(form) do
        fill_in "slack_webhook_url", with: ""
        click_button "[update]"
      end
      expect(page).to have_content("Slack webhook cleared.")
      record = NotificationDeliveryChannel.find_by(kind: "slack")
      expect(record.webhook_url).to be_nil
      expect(record.everything).to be(false)
      expect(record.daily_digest).to be(false)
    end
  end

  describe "the Discord pane" do
    it "renders the webhook URL field and the routing checkboxes" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Discord']]") do
        expect(page).to have_field("discord_webhook_url")
        expect(page).to have_field("everything", type: "checkbox")
        expect(page).to have_field("daily_digest", type: "checkbox")
        expect(page).to have_button("[update]")
      end
    end

    it "saves a webhook URL and shows the saved confirmation" do
      stub_request(:post, discord_url).to_return(status: 204, body: "")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='discord_webhook_url']]")
      within(form) do
        fill_in "discord_webhook_url", with: discord_url
        check "everything"
        click_button "[update]"
      end
      expect(page).to have_content("Discord webhook updated.")
      expect(NotificationDeliveryChannel.find_by(kind: "discord").webhook_url).to eq(discord_url)
    end

    # 2026-05-16 webhook-clear UX tweak.
    it "renders the `every notification` label (not the old `deliver every notification`)" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Discord']]") do
        expect(page).to have_text("every notification")
        expect(page).not_to have_text("deliver every notification")
        expect(page).to have_text("daily digest")
      end
    end

    # 2026-05-16 webhook-clear UX tweak.
    # Clearing the URL field and hitting `[update]` persists the row
    # with nil URL + both flags off and surfaces the distinct
    # "Discord webhook cleared." flash.
    it "clears the integration on a blank URL submit" do
      NotificationDeliveryChannel.create!(
        kind: "discord", webhook_url: discord_url,
        everything: true, daily_digest: true
      )
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='discord_webhook_url']]")
      within(form) do
        fill_in "discord_webhook_url", with: ""
        click_button "[update]"
      end
      expect(page).to have_content("Discord webhook cleared.")
      record = NotificationDeliveryChannel.find_by(kind: "discord")
      expect(record.webhook_url).to be_nil
      expect(record.everything).to be(false)
      expect(record.daily_digest).to be(false)
    end
  end

  describe "the removed YouTube pane" do
    it "is absent from the Settings page" do
      visit settings_path
      expect(page).not_to have_css("h2", text: "YouTube")
      expect(page).not_to have_field("settings[youtube_api_key]")
      expect(page).not_to have_field("settings[youtube_client_id]")
    end
  end

  # Phase 29 (settings refactor) — the Voyage.ai pane is gone from
  # /settings. Voyage indexing is now gated solely on credentials key
  # presence; no operator-facing toggle remains. The `voyage embeddings`
  # status badge surfaces inside the stack pane (covered by the stack
  # pane view spec).
  describe "the dropped Voyage.ai pane" do
    it "is absent from the Settings page" do
      visit settings_path
      expect(page).not_to have_css("h2", text: "Voyage.ai")
      expect(page).not_to have_field("settings[voyage_index_project_notes]")
    end
  end
end
