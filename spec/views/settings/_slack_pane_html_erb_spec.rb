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

    # 2026-05-17 — the pane was restructured into one URL form plus two
    # tiny auto-save toggle forms, one checkbox per form. Both checkboxes
    # share the field name `enabled` (the `:kind` is in the form's PATCH
    # path, not the field name). The Stimulus / leader-menu hook
    # `data-leader-toggle=` is the stable selector for each individual
    # checkbox.
    it "renders the everything checkbox unchecked" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_every_notification"]:not([checked])'
      )
    end

    it "renders the daily_digest checkbox unchecked" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_daily_digest"]:not([checked])'
      )
    end

    it "renders the [update] submit button" do
      expect(rendered).to include("[update]")
    end

    # 2026-05-16 — the middle-dot `nav-sep` between `[update]` and
    # `[help]` was dropped alongside the muted-bracketed-link primitive
    # rollout (`BracketedMutedLinkComponent`). The visual hierarchy of
    # loud `[update]` next to muted `[help]` carries the grouping on
    # its own; whitespace is the separator now (matches the
    # `[ authorize ] [ cancel ]` pattern on the Doorkeeper consent
    # page). Regression guard: the separator must NOT be reintroduced.
    it "does NOT render a `nav-sep` middle dot between [update] and [help]" do
      expect(rendered).not_to match(
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

    # 2026-05-17 secrets-in-DOM hardening — the URL input NEVER renders
    # the real webhook URL as its `value=""`. When a row is configured,
    # the input ships with `value=""` and shows the masked prefix
    # (`https://hooks.slack.com/***`) as a `placeholder=""` so users see
    # "something is set here" without leaking the secret into HTML view
    # source. Encryption at rest + filtered logs + masked DOM = three
    # legs of the secret defense.
    it "does NOT render the raw URL in the input value (encrypted-at-rest secret)" do
      expect(rendered).not_to include(%(value="#{valid_url}"))
      expect(rendered).to match(%r{<input[^>]*name="slack_webhook_url"[^>]*value=""})
    end

    it "renders the masked URL as the input placeholder" do
      expect(rendered).to include('placeholder="https://hooks.slack.com/***"')
    end

    it "pre-checks the everything checkbox" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_every_notification"][checked]'
      )
    end

    it "pre-checks the daily_digest checkbox" do
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_daily_digest"][checked]'
      )
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
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_every_notification"]:not([checked])'
      )
      expect(rendered).to have_css(
        'input[type="checkbox"][value="yes"][data-leader-toggle="slack_daily_digest"][checked]'
      )
    end
  end

  describe "checkbox wire format" do
    before do
      assign(:slack_webhook, nil)
      render partial: "settings/slack_pane"
    end

    # The auto-save toggle forms post a single `enabled` field per form;
    # the `:kind` ("everything" / "daily_digest") is in the form's PATCH
    # URL, not the field name. The yes/no contract still applies: the
    # checkbox's `value=""` MUST be the literal string `yes`.
    it "uses `yes` as the checkbox value for the everything toggle (yes/no boundary)" do
      expect(rendered).to match(
        %r{<input[^>]*value="yes"[^>]*data-leader-toggle="slack_every_notification"}
      )
      expect(rendered).not_to match(
        %r{<input[^>]*value="(?:true|1|on)"[^>]*data-leader-toggle="slack_every_notification"}
      )
    end

    it "uses `yes` as the checkbox value for the daily_digest toggle" do
      expect(rendered).to match(
        %r{<input[^>]*value="yes"[^>]*data-leader-toggle="slack_daily_digest"}
      )
      expect(rendered).not_to match(
        %r{<input[^>]*value="(?:true|1|on)"[^>]*data-leader-toggle="slack_daily_digest"}
      )
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
