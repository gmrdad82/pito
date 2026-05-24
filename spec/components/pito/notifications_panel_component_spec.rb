require "rails_helper"

RSpec.describe Pito::NotificationsPanelComponent, type: :component do
  subject(:rendered) do
    render_inline(described_class.new(
      discord_webhook: nil,
      slack_webhook: nil
    ))
  end

  let(:root) { rendered.css("section.pito-panel").first }

  it "renders the canonical pito-panel section wrapper" do
    expect(root).to be_present
    expect(root["class"]).to include("pito-panel")
    expect(root["class"]).to include("pito-panel--notifications")
  end

  it "resolves the title from the canonical home-panel i18n namespace" do
    expect(I18n.t("tui.home.panels.notifications.title")).to eq("notifications settings")
    title_span = rendered.css(".pito-pane__title").first
    expect(title_span).to be_present
    expect(title_span.text.strip).to eq("notifications settings")
  end

  it "wires the tui-panel-cable Stimulus controller" do
    expect(root["data-controller"]).to include("tui-panel-cable")
  end

  it "emits the canonical cable name + screen data values" do
    expect(root["data-tui-panel-cable-name-value"]).to eq("notifications")
    expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
  end

  it "registers the panel as a tui-cursor target" do
    expect(root["data-tui-cursor-target"]).to eq("panel")
  end

  it "emits the panel name into both cable + panel scope data values" do
    expect(root["data-tui-panel-name-value"]).to eq("notifications")
  end

  it "joins the locked focusables list (with notifications_sync leading) into the panel data value" do
    expect(root["data-tui-panel-focusables-value"]).to eq(
      "notifications_sync,all,daily,discord_webhook,discord_update,discord_help,slack_webhook,slack_update,slack_help"
    )
  end

  it "JSON-encodes an empty keybinds Hash into the panel data value" do
    expect(root["data-tui-panel-keybinds-value"]).to eq("{}")
  end

  describe "#cable_channel_for" do
    it "derives the canonical pito:home:notifications stream name" do
      component = described_class.new(discord_webhook: nil, slack_webhook: nil)
      expect(component.cable_channel_for(described_class::PANEL_NAME)).to eq("pito:home:notifications")
    end
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:notifications)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  it "no longer defines the legacy CABLE_CHANNEL constant (Phase 2C cleanup)" do
    expect(described_class.const_defined?(:CABLE_CHANNEL)).to be(false)
  end

  describe "global text-color taxonomy (2026-05-24)" do
    # Per CLAUDE.md + docs/design.md, the locked rule is:
    #   - data values        → --color-text (white)
    #   - labels / captions  → --color-muted
    #   - titles + actions   → --section-accent
    #
    # On this panel:
    #   "Discord" / "Slack" brand subsection headings = LABEL captions
    #   "webhook URL:" form labels                    = LABEL captions
    #   "[ ] all" / "[x] daily digest" checkboxes     = ACTIONS (whole compound)
    it "renders the Discord brand heading with the muted-label class hook" do
      heading = rendered.css("h3.notifications-brand__heading").first
      expect(heading).to be_present
      expect(heading.text.strip).to eq(I18n.t("settings.discord.heading"))
    end

    it "renders the Slack brand heading with the muted-label class hook" do
      headings = rendered.css("h3.notifications-brand__heading").map { |n| n.text.strip }
      expect(headings).to include(I18n.t("settings.slack.heading"))
    end

    it "renders both brand headings with the same canonical class (one CSS rule covers both)" do
      headings = rendered.css("h3.notifications-brand__heading")
      expect(headings.size).to eq(2)
      headings.each do |h|
        expect(h["class"]).to include("notifications-brand__heading")
      end
    end

    it "renders the Discord webhook URL field-label with the canonical .form-label hook" do
      label = rendered.css('label[for="discord_webhook_url"]').first
      expect(label).to be_present
      expect(label["class"]).to include("form-label")
    end

    it "renders the Slack webhook URL field-label with the canonical .form-label hook" do
      label = rendered.css('label[for="slack_webhook_url"]').first
      expect(label).to be_present
      expect(label["class"]).to include("form-label")
    end

    it "renders `[ ] all` and `[x] daily digest` as `.md-check` compounds with both indicator + label slots present" do
      checkboxes = rendered.css("label.md-check")
      expect(checkboxes.size).to be >= 2
      checkboxes.first(2).each do |cb|
        expect(cb.css(".md-check-indicator")).to be_present
        expect(cb.css(".md-check-label")).to be_present
      end
    end
  end

  describe "#panel_commands (Phase 1C — section-specific palette)" do
    subject(:commands) { described_class.new(discord_webhook: nil, slack_webhook: nil).panel_commands }

    it "returns an Array of Hash entries" do
      expect(commands).to be_an(Array)
      expect(commands).to all(be_a(Hash))
    end

    it "carries the locked notification command set" do
      keys = commands.map { |c| c[:key] }
      expect(keys).to contain_exactly(
        "toggle_all",
        "toggle_daily_digest",
        "focus_discord_webhook",
        "focus_slack_webhook",
        "sync_toggle_notifications"
      )
    end

    it "wires each command to a registered action_name" do
      commands.each do |c|
        expect(c[:action_name]).to be_a(Symbol)
        expect { Pito::ActionRegistry[c[:action_name]] }.not_to raise_error
      end
    end

    it "serializes into the panel root's data-panel-commands attribute" do
      raw = root["data-panel-commands"]
      expect(raw).to be_present
      parsed = JSON.parse(raw)
      expect(parsed.length).to eq(5)
      expect(parsed.first["key"]).to eq("toggle_all")
    end
  end
end
