# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Footage::ProbeCommandComponent, type: :component do
  let(:game) { build(:game, id: 42) }

  it "renders the probe command with game id in the code element" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css("code").text).to include('rails pito:tools:probe game=42 path="/clips/*"')
  end

  it "shows the alt+c keyboard shortcut hint" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.text).to include("alt+c to copy")
  end

  it "includes the pito--footage-import stimulus controller" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css('[data-controller="pito--footage-import"]')).not_to be_empty
  end

  it "stores the command text as a data-pito--footage-import-command-value" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css('[data-pito--footage-import-command-value*="pito:tools:probe"]')).not_to be_empty
  end

  it "stores the feedback variants as JSON in data-pito--footage-import-feedback-value" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    el = node.css('[data-pito--footage-import-feedback-value]').first
    expect(el).not_to be_nil
    parsed = JSON.parse(el["data-pito--footage-import-feedback-value"])
    expect(parsed).to be_an(Array)
    expect(parsed.size).to eq(50)
  end

  it "has the pito-footage-import class on the root element" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css(".pito-footage-import")).not_to be_empty
  end

  it "is keyboard-focusable via Tab (tabindex=0)" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css('[tabindex="0"]')).not_to be_empty
  end

  it "code element uses text-fg class for readable contrast" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    code = node.css("code").first
    expect(code["class"]).to include("text-fg")
  end

  it "places the alt+c hint outside the bordered box" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    box = node.css(".pito-footage-import__box").first
    expect(box).not_to be_nil
    # The hint text lives on the root, not inside the bordered box.
    expect(box.text).not_to include("alt+c")
    expect(node.text).to include("alt+c to copy")
  end

  it "has an overlay target element" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css('[data-pito--footage-import-target="overlay"]')).not_to be_empty
  end

  it "uses the custom path when provided" do
    node = render_inline(described_class.new(game_id: game.id, path: "/custom"))
    expect(node.css("code").text).to include('pito:tools:probe game=42 path="/custom/*"')
  end

  it "appends -- --force to command_text when force: true" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips", force: true))
    text = node.css("code").text
    expect(text).to include('game=42')
    expect(text).to include('path="/clips/*"')
    expect(text).to end_with("-- --force")
  end

  it "does not include --force in command_text when force is omitted" do
    node = render_inline(described_class.new(game_id: game.id, path: "/clips"))
    expect(node.css("code").text).not_to include("--force")
  end
end
