require "rails_helper"

# Phase 26 — 01b. Slack pane partial. Mirror of the Discord pane —
# pre-fills the URL field from the AR row (`@slack_webhook`),
# pre-checks `everything` / `daily_digest` from the same row, and
# submits to `PATCH /settings/slack_webhook`. The partial reads the
# same instance variable from the SettingsController action.
RSpec.describe "settings/_slack_pane.html.erb", type: :view do
  let(:valid_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }

  describe "with no AR row (greenfield install)" do
    before do
      assign(:slack_webhook, nil)
      render partial: "settings/slack_pane"
    end

    it "renders the Slack heading" do
      expect(rendered).to include("<h2>Slack</h2>")
    end

    it "renders an empty URL input" do
      expect(rendered).to match(%r{<input[^>]*name="slack_webhook_url"[^>]*value=""})
    end

    it "renders the everything checkbox unchecked" do
      expect(rendered).to match(%r{<input[^>]*name="everything"[^>]*value="yes"(?![^>]*\schecked)})
    end

    it "renders the daily_digest checkbox unchecked" do
      expect(rendered).to match(%r{<input[^>]*name="daily_digest"[^>]*value="yes"(?![^>]*\schecked)})
    end

    it "renders the [update] submit button" do
      expect(rendered).to include("[update]")
    end

    # 2026-05-11 — middle-dot separator between `[update]` and
    # `[help]`, matching the `nav-sep` pattern from the channel show
    # page (between the in-app `[+]` and the external
    # `[youtube channel]`).
    it "renders a `nav-sep` middle dot between [update] and [help]" do
      expect(rendered).to match(
        %r{\[update\].*<span class="nav-sep" aria-hidden="true">·</span>.*\[help\]}m
      )
    end

    it "submits to `PATCH /settings/slack_webhook`" do
      expect(rendered).to include('action="/settings/slack_webhook"')
      # Rails encodes PATCH as a `_method` hidden field on a form-with
      # local: true form.
      expect(rendered).to match(/name="_method"\s+value="patch"/)
    end

    it "carries the daily-digest hint copy" do
      expect(rendered).to include("sent daily at 09:00 in your time zone")
    end
  end

  describe "with an AR row (URL + both flags on)" do
    before do
      record = NotificationDeliveryChannel.create!(
        kind: "slack", webhook_url: valid_url,
        everything: true, daily_digest: true
      )
      assign(:slack_webhook, record)
      render partial: "settings/slack_pane"
    end

    it "pre-fills the URL input from the AR row" do
      expect(rendered).to include(%(value="#{valid_url}"))
    end

    it "pre-checks the everything checkbox" do
      expect(rendered).to match(%r{<input[^>]*name="everything"[^>]*value="yes"[^>]*\schecked})
    end

    it "pre-checks the daily_digest checkbox" do
      expect(rendered).to match(%r{<input[^>]*name="daily_digest"[^>]*value="yes"[^>]*\schecked})
    end
  end

  describe "with an AR row (one flag on, one off)" do
    before do
      record = NotificationDeliveryChannel.create!(
        kind: "slack", webhook_url: valid_url,
        everything: false, daily_digest: true
      )
      assign(:slack_webhook, record)
      render partial: "settings/slack_pane"
    end

    it "pre-checks `daily_digest` only" do
      expect(rendered).to match(%r{<input[^>]*name="everything"[^>]*value="yes"(?![^>]*\schecked)})
      expect(rendered).to match(%r{<input[^>]*name="daily_digest"[^>]*value="yes"[^>]*\schecked})
    end
  end

  describe "checkbox wire format" do
    before do
      assign(:slack_webhook, nil)
      render partial: "settings/slack_pane"
    end

    it "uses `yes` as the checkbox value for `everything` (yes/no boundary)" do
      expect(rendered).to match(%r{<input[^>]*name="everything"[^>]*value="yes"})
      expect(rendered).not_to match(%r{<input[^>]*name="everything"[^>]*value="(?:true|1|on)"})
    end

    it "uses `yes` as the checkbox value for `daily_digest`" do
      expect(rendered).to match(%r{<input[^>]*name="daily_digest"[^>]*value="yes"})
      expect(rendered).not_to match(%r{<input[^>]*name="daily_digest"[^>]*value="(?:true|1|on)"})
    end
  end

  describe "no forbidden JS confirm hooks" do
    before do
      assign(:slack_webhook, nil)
      render partial: "settings/slack_pane"
    end

    it "does NOT render data-turbo-confirm" do
      # CLAUDE.md hard rule — no native JS confirm/alert/prompt and no
      # data-turbo-confirm. Destructive surfaces use the action page
      # framework; settings updates are non-destructive and simply
      # submit.
      expect(rendered).not_to include("data-turbo-confirm")
    end
  end
end
