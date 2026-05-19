require "rails_helper"

# Phase 29 — Unit A1. System-level regression for the Settings
# integrations section after the AppSetting → credentials
# consolidation:
#
#   * The Slack + Discord webhook panes still render and still save
#     exactly as before (URL field + "all" /
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
    # 2026-05-19 — Phase D form restructure. The pane was split into
    # one URL form (`PATCH /settings/slack_webhook`) + two per-flag
    # auto-save toggle forms (`PATCH /settings/notification_toggles/
    # slack/<kind>`). Both checkboxes now share `name="enabled"`; the
    # stable selector is the `data-leader-toggle=` attribute that
    # leader-menu and Stimulus key off of. Behavioral coverage of the
    # toggle endpoints lives in the request specs; this system pass
    # only verifies the DOM affordances render under a real browser
    # round-trip.
    it "renders the webhook URL field and both routing-toggle checkboxes" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Slack']]") do
        expect(page).to have_field("slack_webhook_url")
        expect(page).to have_css(
          'input[type="checkbox"][data-leader-toggle="slack_every_notification"]'
        )
        expect(page).to have_css(
          'input[type="checkbox"][data-leader-toggle="slack_daily_digest"]'
        )
        expect(page).to have_button("[update]")
      end
    end

    # 2026-05-19 — Phase D form restructure. The URL form no longer
    # reads `everything` / `daily_digest`; those flags moved to the
    # per-flag auto-save endpoint (covered by request + view specs).
    # The system pass verifies the URL submit path: fill the field,
    # click `[update]`, the test ping fires, and the row persists
    # with the saved confirmation.
    it "saves a webhook URL and shows the saved confirmation" do
      stub_request(:post, slack_url).to_return(status: 200, body: "ok")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='slack_webhook_url']]")
      within(form) do
        fill_in "slack_webhook_url", with: slack_url
        click_button "[update]"
      end
      expect(page).to have_content("Slack updated.")
      expect(NotificationDeliveryChannel.find_by(kind: "slack").webhook_url).to eq(slack_url)
    end

    # 2026-05-16 webhook-clear UX tweak.
    # The first checkbox label dropped its "deliver " prefix — the
    # word was redundant against the surrounding pane copy and the
    # `[update]` button.
    # 2026-05-18 — the bare "every notification" label was further
    # shortened to just "all" to match the leader-popup grid copy
    # ("Slack all" / "Discord all"), keeping the toggle text identical
    # to its keybinding label.
    it "renders the `all` label (not the old `every notification` / `deliver every notification`)" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Slack']]") do
        expect(page).to have_css(".md-check-label", text: "all")
        expect(page).not_to have_text("every notification")
        expect(page).not_to have_text("deliver every notification")
        expect(page).to have_css(".md-check-label", text: "daily digest")
      end
    end

    # 2026-05-19 — webhook-clear UX contract changed. With the input
    # value masking rollout (FA-era hardening), the field always
    # submits empty unless the operator types something new — so
    # blank submissions became a no-op ("Slack unchanged.") to stop
    # every page-level save from silently wiping the URL. The
    # cooperating clear gesture is now the literal word `clear`
    # (case-insensitive) typed into the URL field; the controller
    # persists nil URL + both flags off and surfaces the distinct
    # "Slack cleared." flash.
    it "clears the integration when the operator types the `clear` keyword" do
      NotificationDeliveryChannel.create!(
        kind: "slack", webhook_url: slack_url,
        everything: true, daily_digest: true
      )
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='slack_webhook_url']]")
      within(form) do
        fill_in "slack_webhook_url", with: "clear"
        click_button "[update]"
      end
      expect(page).to have_content("Slack cleared.")
      record = NotificationDeliveryChannel.find_by(kind: "slack")
      expect(record.webhook_url).to be_nil
      expect(record.everything).to be(false)
      expect(record.daily_digest).to be(false)
    end
  end

  describe "the Discord pane" do
    # 2026-05-19 — Phase D form restructure. The pane was split into
    # one URL form (`PATCH /settings/discord_webhook`) + two per-flag
    # auto-save toggle forms (`PATCH /settings/notification_toggles/
    # discord/<kind>`). Both checkboxes now share `name="enabled"`;
    # the stable selector is the `data-leader-toggle=` attribute that
    # leader-menu and Stimulus key off of. Behavioral coverage of the
    # toggle endpoints lives in the request specs; this system pass
    # only verifies the DOM affordances render under a real browser
    # round-trip.
    it "renders the webhook URL field and both routing-toggle checkboxes" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Discord']]") do
        expect(page).to have_field("discord_webhook_url")
        expect(page).to have_css(
          'input[type="checkbox"][data-leader-toggle="discord_every_notification"]'
        )
        expect(page).to have_css(
          'input[type="checkbox"][data-leader-toggle="discord_daily_digest"]'
        )
        expect(page).to have_button("[update]")
      end
    end

    # 2026-05-19 — Phase D form restructure. The URL form no longer
    # reads `everything` / `daily_digest`; those flags moved to the
    # per-flag auto-save endpoint (covered by request + view specs).
    # The system pass verifies the URL submit path: fill the field,
    # click `[update]`, the test ping fires, and the row persists
    # with the saved confirmation.
    it "saves a webhook URL and shows the saved confirmation" do
      stub_request(:post, discord_url).to_return(status: 204, body: "")
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='discord_webhook_url']]")
      within(form) do
        fill_in "discord_webhook_url", with: discord_url
        click_button "[update]"
      end
      expect(page).to have_content("Discord updated.")
      expect(NotificationDeliveryChannel.find_by(kind: "discord").webhook_url).to eq(discord_url)
    end

    # 2026-05-16 webhook-clear UX tweak.
    # 2026-05-18 — label shortened from "every notification" to "all"
    # to match the leader-popup grid copy ("Discord all").
    it "renders the `all` label (not the old `every notification` / `deliver every notification`)" do
      visit settings_path
      within(:xpath, "//fieldset[.//h2[text()='Discord']]") do
        expect(page).to have_css(".md-check-label", text: "all")
        expect(page).not_to have_text("every notification")
        expect(page).not_to have_text("deliver every notification")
        expect(page).to have_css(".md-check-label", text: "daily digest")
      end
    end

    # 2026-05-19 — webhook-clear UX contract changed. With the input
    # value masking rollout (FA-era hardening), the field always
    # submits empty unless the operator types something new — so
    # blank submissions became a no-op ("Discord unchanged.") to stop
    # every page-level save from silently wiping the URL. The
    # cooperating clear gesture is now the literal word `clear`
    # (case-insensitive) typed into the URL field; the controller
    # persists nil URL + both flags off and surfaces the distinct
    # "Discord cleared." flash.
    it "clears the integration when the operator types the `clear` keyword" do
      NotificationDeliveryChannel.create!(
        kind: "discord", webhook_url: discord_url,
        everything: true, daily_digest: true
      )
      visit settings_path
      form = find(:xpath, "//form[.//input[@name='discord_webhook_url']]")
      within(form) do
        fill_in "discord_webhook_url", with: "clear"
        click_button "[update]"
      end
      expect(page).to have_content("Discord cleared.")
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
