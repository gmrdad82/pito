# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Footage::ProbeCommandComponent, type: :component do
  let(:game) { build(:game, id: 42) }

  it "renders the probe command with game id" do
    node = render_inline(described_class.new(game_id: game.id))
    expect(node.css("code").text).to include('cd /path/to/footage && rails pito:tools:probe game=42 path="*"')
  end

  it "shows the keyboard shortcut hint" do
    node = render_inline(described_class.new(game_id: game.id))
    expect(node.text).to include("Ctrl+C to copy")
  end

  it "includes the clipboard stimulus controller" do
    node = render_inline(described_class.new(game_id: game.id))
    expect(node.css('[data-controller="clipboard"]')).not_to be_empty
  end

  it "stores the command text as a data value" do
    node = render_inline(described_class.new(game_id: game.id))
    expect(node.css('[data-clipboard-text-value*="pito:tools:probe"]')).not_to be_empty
  end

  it "is keyboard-focusable via Tab" do
    node = render_inline(described_class.new(game_id: game.id))
    expect(node.css('[tabindex="0"]')).not_to be_empty
  end

  it "uses the custom path when provided" do
    node = render_inline(described_class.new(game_id: game.id, path: "/custom"))
    expect(node.css("code").text).to include('cd /custom && rails pito:tools:probe game=42 path="*"')
  end
end
