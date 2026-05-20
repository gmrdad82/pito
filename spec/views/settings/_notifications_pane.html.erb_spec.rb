require "rails_helper"

# Beta 4 — F3-B-SIMPLIFY-MODEL (2026-05-20). Unified notifications
# panel partial.
#
# Renders the V1 layout (toggles top, Discord middle, Slack bottom).
# Reads two instance variables from `SettingsController#index` for the
# brand webhooks AND the shared toggle state from
# `AppSetting.singleton_row`.
RSpec.describe "settings/_notifications_pane.html.erb", type: :view do
  let(:discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }

  before { AppSetting.delete_all }

  describe "with no AR rows (greenfield install)" do
    before do
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "renders the notifications heading (lowercase, bold via <strong>)" do
      expect(rendered).to match(%r{<h2><strong>notifications</strong></h2>})
    end

    it "renders both shared toggle checkboxes unchecked" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="notification_all"]:not([checked])'
      )
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="notification_daily_digest"]:not([checked])'
      )
    end

    it "renders the `all` and `daily digest` labels" do
      expect(rendered).to have_css(".md-check-label", text: "all")
      expect(rendered).to have_css(".md-check-label", text: "daily digest")
    end

    it "renders the daily-digest hint copy next to the toggle" do
      expect(rendered).to include("sent daily at 09:00 in your time zone")
    end

    it "renders both brand subsections (Discord then Slack)" do
      expect(rendered).to have_css("h3", text: "Discord")
      expect(rendered).to have_css("h3", text: "Slack")
      # Discord must come before Slack in the DOM (V1 stack order).
      expect(rendered.index("Discord")).to be < rendered.index("Slack")
    end

    it "renders empty URL inputs for both brands" do
      expect(rendered).to match(%r{<input[^>]*name="discord_webhook_url"[^>]*value=""})
      expect(rendered).to match(%r{<input[^>]*name="slack_webhook_url"[^>]*value=""})
    end

    it "renders [update] buttons in both brand subsections" do
      expect(rendered.scan("[update]").length).to be >= 2
    end

    it "renders [help] muted links in both brand subsections" do
      expect(rendered.scan(/\[<span class="bl">help<\/span>\]/).length).to eq(2)
    end

    it "submits each brand form to the new unified controller" do
      expect(rendered).to include('action="/settings/notifications/discord"')
      expect(rendered).to include('action="/settings/notifications/slack"')
    end

    it "renders the clear-keyword hint copy" do
      expect(rendered).to include('type <strong>"clear"</strong> to remove')
    end

    it "submits shared toggle forms to the new shared toggle endpoint" do
      expect(rendered).to include('action="/settings/notification_toggles/all"')
      expect(rendered).to include('action="/settings/notification_toggles/daily_digest"')
    end
  end

  describe "with shared toggles ON and both AR rows configured" do
    before do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      AppSetting.set_notification_toggle!(:notifications_send_daily_digest, true)
      assign(:discord_webhook, NotificationDeliveryChannel.create!(
        kind: "discord", webhook_url: discord_url
      ))
      assign(:slack_webhook, NotificationDeliveryChannel.create!(
        kind: "slack", webhook_url: slack_url
      ))
      render partial: "settings/notifications_pane"
    end

    it "renders both shared toggle checkboxes as checked (singleton row drives state)" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="notification_all"][checked]'
      )
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="notification_daily_digest"][checked]'
      )
    end

    it "renders the masked URL placeholders (never the real URL)" do
      expect(rendered).not_to include(%(value="#{discord_url}"))
      expect(rendered).not_to include(%(value="#{slack_url}"))
      expect(rendered).to include('placeholder="https://discord.com/***"')
      expect(rendered).to include('placeholder="https://hooks.slack.com/***"')
    end

    it "still ships URL inputs with empty values (encryption-at-rest secret never leaks)" do
      expect(rendered).to match(%r{<input[^>]*name="discord_webhook_url"[^>]*value=""})
      expect(rendered).to match(%r{<input[^>]*name="slack_webhook_url"[^>]*value=""})
    end
  end

  describe "shared toggle independence from webhook configuration" do
    # 2026-05-20 — F3-B-SIMPLIFY-MODEL. The shared toggle reads ONLY
    # the singleton row; it does NOT require a webhook to be on.
    before do
      AppSetting.set_notification_toggle!(:notifications_send_all, true)
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "renders the `all` toggle as checked even with no brand rows" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="notification_all"][checked]'
      )
    end
  end

  describe "checkbox wire format (yes/no boundary)" do
    before do
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "uses `yes` as the checkbox value for `all`" do
      expect(rendered).to match(
        %r{<input[^>]*value="yes"[^>]*data-leader-toggle="notification_all"}
      )
      expect(rendered).not_to match(
        %r{<input[^>]*value="(?:true|1|on)"[^>]*data-leader-toggle="notification_all"}
      )
    end

    it "uses `yes` as the checkbox value for `daily_digest`" do
      expect(rendered).to match(
        %r{<input[^>]*value="yes"[^>]*data-leader-toggle="notification_daily_digest"}
      )
    end
  end

  describe "no forbidden JS confirm hooks" do
    before do
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "does NOT render data-turbo-confirm" do
      expect(rendered).not_to include("data-turbo-confirm")
    end
  end

  describe "F3-B-TOGGLE-FEEDBACK braille spinner wiring" do
    # 2026-05-20 — each shared toggle wraps its `md-check` label in a
    # `tui-toggle-feedback` Stimulus controller that hides the
    # `[x]`/`[ ]` glyph and reveals a sibling braille indicator while
    # the auto-save form is in flight. The spinner element ships
    # `hidden` at SSR time; the controller flips it on `change` and
    # off on `turbo:submit-end`.
    before do
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "mounts the tui-toggle-feedback controller on each toggle label" do
      expect(rendered.scan('data-controller="tui-toggle-feedback"').length).to eq(2)
    end

    it "registers the checkbox input as the controller's `checkbox` target" do
      expect(rendered).to have_css(
        'input[type="checkbox"][data-tui-toggle-feedback-target="checkbox"][data-leader-toggle="notification_all"]'
      )
      expect(rendered).to have_css(
        'input[type="checkbox"][data-tui-toggle-feedback-target="checkbox"][data-leader-toggle="notification_daily_digest"]'
      )
    end

    it "registers the md-check-indicator glyph as the controller's `glyph` target" do
      expect(rendered).to have_css(
        'span.md-check-indicator[data-tui-toggle-feedback-target="glyph"]', count: 2
      )
    end

    it "renders the spinner element hidden at SSR (no glyph swap until click)" do
      # `[hidden]` elements are non-visible to Capybara's default
      # filter, so we count the literal markup instead. Two toggles
      # render two spinner wrappers, both shipped with `hidden`.
      expect(rendered.scan(/<span class="md-check-spinner"[^>]*data-tui-toggle-feedback-target="spinner"[^>]*hidden/).length).to eq(2)
    end

    it "mounts a braille indicator inside each spinner slot" do
      expect(rendered.scan(/tui-indicator--braille/).length).to be >= 2
      expect(rendered.scan(/tui-indicator--indeterminate/).length).to be >= 2
    end

    it "de-syncs the two spinners via distinct start_offset values" do
      # Both indicators share the controller but start_offset differs
      # (0 for `all`, 3 for `daily_digest`) so the dots don't beat in
      # unison on the page.
      expect(rendered).to include('data-tui-indicator-start-offset-value="0"')
      expect(rendered).to include('data-tui-indicator-start-offset-value="3"')
    end
  end

  describe "hairline separators between sections" do
    before do
      assign(:discord_webhook, nil)
      assign(:slack_webhook, nil)
      render partial: "settings/notifications_pane"
    end

    it "renders <hr> elements between the toggles block and the brand sections" do
      # V1 layout: toggles | hairline | Discord | hairline | Slack.
      # Two <hr> elements total.
      expect(rendered.scan(/<hr\b/).length).to eq(2)
    end
  end
end
