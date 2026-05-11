require "rails_helper"

# Phase 26 — 01d. The help-modal fragment view. The controller assigns
# `@provider` (the validated slug) and `@markdown` (the raw .md file
# contents); the template renders the Markdown via
# `ApplicationHelper#render_markdown` (Commonmarker, hardbreaks: true)
# and wraps the result in the layout's `<turbo-frame>` id so Turbo
# swaps it into the dialog.
RSpec.describe "settings/webhooks/help/show.html.erb", type: :view do
  describe "Slack guide" do
    before do
      assign(:provider, "slack")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders the Slack heading as <h1>" do
      expect(rendered).to include("<h1>Slack webhook setup</h1>")
    end

    it "renders the four step <h2> headings" do
      expect(rendered).to include("Step 1")
      expect(rendered).to include("Step 2")
      expect(rendered).to include("Step 3")
      expect(rendered).to include("Step 4")
    end

    it "renders the indented code block for the webhook URL example" do
      # Markdown's four-space-indented `https://hooks.slack.com/...`
      # block becomes `<pre><code>` after rendering.
      expect(rendered).to include("<pre>")
      expect(rendered).to include("hooks.slack.com")
    end

    it "wraps content in the modal Turbo Frame" do
      expect(rendered).to include('id="webhook_help_modal_frame"')
    end

    it "carries the per-provider data attribute" do
      expect(rendered).to include('data-webhook-help="slack"')
    end
  end

  describe "Discord guide" do
    before do
      assign(:provider, "discord")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders the Discord heading as <h1>" do
      expect(rendered).to include("<h1>Discord webhook setup</h1>")
    end

    it "renders the three step <h2> headings" do
      expect(rendered).to include("Step 1")
      expect(rendered).to include("Step 2")
      expect(rendered).to include("Step 3")
    end

    it "renders the indented code block for the webhook URL example" do
      expect(rendered).to include("<pre>")
      expect(rendered).to include("discord.com/api/webhooks")
    end

    it "carries the per-provider data attribute" do
      expect(rendered).to include('data-webhook-help="discord"')
    end
  end

  describe "Markdown source files" do
    it "ships the Slack guide as an on-disk `.md` file" do
      path = Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md")
      expect(path).to exist
      content = path.read
      # Key phrases the beginner-friendly contract requires.
      expect(content).to include("Create a Slack app")
      expect(content).to include("Add New Webhook to Workspace")
      expect(content).to include("hooks.slack.com")
    end

    it "ships the Discord guide as an on-disk `.md` file" do
      path = Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md")
      expect(path).to exist
      content = path.read
      expect(content).to include("Create a webhook")
      expect(content).to include("Copy Webhook URL")
      expect(content).to include("discord.com/api/webhooks")
    end
  end

  # Phase 26 — 01d acceptance: the spec mandates a Troubleshooting
  # section in each guide covering invalid-URL meaning, ping-failed
  # meaning, the channel-deleted scenario, and (Discord-only)
  # permission errors. These specs lock that surface in so guide
  # drift can't silently drop the safety-net.
  describe "Slack troubleshooting section" do
    before do
      assign(:provider, "slack")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "slack.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders a Troubleshooting heading" do
      expect(rendered).to include("Troubleshooting")
    end

    it "covers the invalid-URL error path" do
      expect(rendered).to include("webhook URL is invalid")
    end

    it "covers the ping-failed / channel-deleted error path" do
      expect(rendered).to include("test ping failed")
      expect(rendered).to match(/404|410|deleted/)
    end

    it "tells the reader how to start over" do
      expect(rendered).to match(/start over|clear the .*webhook URL/i)
    end
  end

  describe "Discord troubleshooting section" do
    before do
      assign(:provider, "discord")
      assign(:markdown,
        Rails.root.join("app", "views", "settings", "webhooks", "help", "discord.md").read)
      render template: "settings/webhooks/help/show", layout: false
    end

    it "renders a Troubleshooting heading" do
      expect(rendered).to include("Troubleshooting")
    end

    it "covers the invalid-URL error path" do
      expect(rendered).to include("webhook URL is invalid")
    end

    it "covers the ping-failed / channel-deleted error path" do
      expect(rendered).to include("test ping failed")
    end

    it "covers the Manage Webhooks permission error specific to Discord" do
      expect(rendered).to include("Manage Webhooks")
    end

    it "documents that both discord.com and discordapp.com hosts are accepted" do
      # Phase 26 — 01c's URL regex accepts both host forms; the guide
      # should call this out so beginners with the older URL don't
      # think they have a bad webhook.
      expect(rendered).to include("discordapp.com")
    end
  end

  describe "polish — no emoji + lowercase prose convention" do
    %w[slack discord].each do |provider|
      it "ships the #{provider} guide with no emoji glyphs" do
        path = Rails.root.join("app", "views", "settings", "webhooks", "help", "#{provider}.md")
        content = path.read
        # Emoji are blocked by the project copy convention. The
        # regex covers the Misc Symbols / Pictographs and Emoticons
        # ranges that cover ~99% of common emoji.
        emoji_re = /[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/
        expect(content).not_to match(emoji_re)
      end
    end
  end
end
