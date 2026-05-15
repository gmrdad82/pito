require "rails_helper"

# Phase 29 — Unit A1. System-level regression for the Settings
# integrations section after the AppSetting → credentials
# consolidation:
#
#   * The Slack + Discord webhook panes still render and still save
#     exactly as before (URL field + "deliver every notification" /
#     "daily digest" checkboxes + `[update]` + the "... webhook saved."
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
# Phase 29 — Unit A2. The auto-signed-in system-spec user is now
# always TOTP-configured (mandatory-2FA gate), so the webhook write
# panes are guarded by `RecentTotpVerification` — a save needs a
# fresh `totp_code`. In the browser the layout-level `totp-modal`
# Stimulus controller injects that hidden field on submit; `rack_test`
# runs no JS, so the spec injects the hidden `totp_code` input into
# the pane form node directly (mirroring exactly what the modal does)
# before clicking `[update]`. The auto-signed-in user carries the
# known seed `JBSWY3DPEHPK3PXP` from `spec/support/auth.rb`.
RSpec.describe "Settings integrations panes (Unit A1)", type: :system do
  before { driven_by(:rack_test) }

  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }

  # `rack_test` runs no JS, so the `totp-modal` controller never fires.
  # Inject the hidden `totp_code` field into the pane form node the
  # same way the modal would, then submit.
  def inject_totp_code(form_node)
    form_node.native.add_child(
      %(<input type="hidden" name="totp_code" value="#{ROTP::TOTP.new(seed).now}">)
    )
  end

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
      @auto_signed_in_user.update_columns(totp_last_used_step: nil)
      stub_request(:post, slack_url).to_return(status: 200, body: "ok")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='slack_webhook_url']]")
      within(form) do
        fill_in "slack_webhook_url", with: slack_url
        check "everything"
      end
      inject_totp_code(form)
      within(form) { click_button "[update]" }
      expect(page).to have_content("Slack webhook saved.")
      expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(slack_url)
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
      @auto_signed_in_user.update_columns(totp_last_used_step: nil)
      stub_request(:post, discord_url).to_return(status: 204, body: "")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='discord_webhook_url']]")
      within(form) do
        fill_in "discord_webhook_url", with: discord_url
        check "everything"
      end
      inject_totp_code(form)
      within(form) { click_button "[update]" }
      expect(page).to have_content("Discord webhook saved.")
      expect(NotificationDeliveryChannel.find_by(kind: "discord").webhook_url).to eq(discord_url)
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

  describe "the slimmed Voyage.ai pane" do
    it "renders the pane but no API key field" do
      visit settings_path
      expect(page).to have_css("h2", text: "Voyage.ai")
      expect(page).not_to have_field("settings[voyage_api_key]")
      expect(page).not_to have_field("settings[clear_voyage_api_key]")
    end

    it "shows the project-notes indexing toggle once a Voyage key is configured in credentials" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:voyage, :api_key).and_return("vk_from_creds")
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Voyage.ai']]") do
        expect(page).to have_field("settings[voyage_index_project_notes]", type: "radio")
      end
    end
  end
end
