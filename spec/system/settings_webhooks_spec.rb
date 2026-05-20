require "rails_helper"

# Beta 4 — F3-B. Unified notifications panel system-level regression.
#
# After the F3-B consolidation the two per-brand panes (Discord +
# Slack) were collapsed into a single notifications panel. The panel
# renders:
#
#   * <h2>notifications</h2> heading
#   * Shared toggles block ([x] all / [x] daily digest)
#   * Discord subsection (<h3>Discord</h3> + URL form)
#   * Slack subsection   (<h3>Slack</h3>   + URL form)
#
# Driven by `rack_test` — the panel is plain forms, no JS needed for
# the submit path. The Slack / Discord test ping is stubbed at the
# HTTP boundary.
RSpec.describe "Settings notifications panel (F3-B)", type: :system do
  before { driven_by(:rack_test) }

  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

  describe "panel chrome" do
    it "renders the notifications heading and the two shared toggles" do
      visit settings_path
      expect(page).to have_css("span.pito-pane__title", text: "notifications")
      expect(page).to have_css(
        'input[type="checkbox"][data-leader-toggle="notification_all"]'
      )
      expect(page).to have_css(
        'input[type="checkbox"][data-leader-toggle="notification_daily_digest"]'
      )
    end

    it "renders both brand subsections under the toggles" do
      visit settings_path
      expect(page).to have_css("h3", text: "Discord")
      expect(page).to have_css("h3", text: "Slack")
    end
  end

  describe "Discord subsection" do
    it "renders the webhook URL field and the [update] button" do
      visit settings_path
      within(:xpath, "//form[.//input[@name='discord_webhook_url']]") do
        expect(page).to have_field("discord_webhook_url")
        expect(page).to have_button("[update]")
      end
    end

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

  describe "Slack subsection" do
    it "renders the webhook URL field and the [update] button" do
      visit settings_path
      within(:xpath, "//form[.//input[@name='slack_webhook_url']]") do
        expect(page).to have_field("slack_webhook_url")
        expect(page).to have_button("[update]")
      end
    end

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

  describe "shared toggle labels" do
    # The shared toggles block at the top of the panel reads `[x] all`
    # and `[x] daily digest`. The legacy `every notification` /
    # `deliver every notification` labels are gone.
    it "renders the `all` and `daily digest` labels (no legacy copy)" do
      visit settings_path
      expect(page).to have_css(".md-check-label", text: "all")
      expect(page).to have_css(".md-check-label", text: "daily digest")
      expect(page).not_to have_text("every notification")
      expect(page).not_to have_text("deliver every notification")
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

  describe "the dropped Voyage.ai pane" do
    it "is absent from the Settings page" do
      visit settings_path
      expect(page).not_to have_css("h2", text: "Voyage.ai")
      expect(page).not_to have_field("settings[voyage_index_project_notes]")
    end
  end
end
