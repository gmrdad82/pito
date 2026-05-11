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
end
