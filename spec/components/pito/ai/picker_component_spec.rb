# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Ai::PickerComponent, type: :component do
  let(:providers) do
    [
      { provider: "opencode", label: "OpenCode Zen", key_present: true, reasoning: "none",
        models: [ { id: "m-1", pinned: false }, { id: "m-2", pinned: false } ] },
      { provider: "openrouter", label: "OpenRouter", key_present: false, reasoning: "passthrough",
        models: [ { id: "or-1", pinned: true } ] }
    ]
  end

  def render_picker(**overrides)
    render_inline(described_class.new(**{
      providers:       providers,
      active_provider: "opencode",
      active_model:    "m-1",
      effort:          nil,
      favorites:       [],
      recents:         []
    }.merge(overrides)))
  end

  it "leads with a Conversation section listing this conversation's used models, only when any exist" do
    node = render_picker(conversation_models: [ "opencode/m-2" ])
    section = node.css('[data-section="conversation"]')
    expect(section).not_to be_empty
    expect(section.text).to include("Conversation")
    expect(section.text).to include("m-2")

    expect(render_picker.css('[data-section="conversation"]')).to be_empty
  end

  it "renders one section per provider, in order, with labels" do
    node = render_picker
    sections = node.css('[data-section="provider"]')
    expect(sections.map { |s| s["data-provider"] }).to eq(%w[opencode openrouter])
    expect(node.text).to include("OpenCode Zen", "OpenRouter")
  end

  it "shows the masked chip for a keyed provider and 'no key' for a keyless one" do
    node = render_picker
    chips = node.css("[data-pito--ai-picker-target=keyChip]")
    expect(chips.find { |c| c["data-provider"] == "opencode" }.text).to include("●●●●")
    expect(chips.find { |c| c["data-provider"] == "openrouter" }.text).to include("no key")
  end

  it "marks the active provider+model row with ● and no other" do
    node    = render_picker
    rows    = node.css('[data-row-type="model"]').to_a
    active  = rows.find { |r| r["data-provider"] == "opencode" && r["data-value"] == "m-1" }
    others  = rows - [ active ]
    expect(active.css("span").first.text).to eq("●")
    expect(others.map { |r| r.css("span").first.text }).to all(eq(""))
  end

  it "shows the key-gate copy line — not pinned rows — for a keyless provider with no models" do
    keyless = [ { provider: "huggingface", label: "Hugging Face", key_present: false,
                  reasoning: "none", models: [] } ]
    node = render_inline(described_class.new(
      providers: keyless, active_provider: "opencode", active_model: nil, effort: nil
    ))

    section = node.css('[data-section="provider"][data-provider="huggingface"]').first
    expect(section.text).to include("Models will load once a key is added.")
    expect(section.css('[data-row-type="model"]')).to be_empty
  end

  it "badges pinned models" do
    node = render_picker
    pinned = node.css('[data-row-type="model"]').find { |r| r["data-value"] == "or-1" }
    expect(pinned.text).to include("pinned")
  end

  it "hides the connect row for keyed providers and shows it for keyless ones" do
    node = render_picker
    connects = node.css('[data-row-type="connect"]')
    expect(connects.find { |r| r["data-provider"] == "opencode" }.has_attribute?("hidden")).to be(true)
    expect(connects.find { |r| r["data-provider"] == "openrouter" }.has_attribute?("hidden")).to be(false)
  end

  it "renders a hidden per-provider password input" do
    node = render_picker
    inputs = node.css("input[type=password]")
    expect(inputs.map { |i| i["data-provider"] }).to match_array(%w[opencode openrouter])
    expect(inputs.map { |i| i.has_attribute?("hidden") }).to all(be(true))
  end

  it "resolves favorites and recents into leading sections, skipping unknown providers" do
    node = render_picker(favorites: [ "opencode/m-2", "ghost/x" ], recents: [ "openrouter/or-1" ])
    fav = node.css('[data-section="favorites"]')
    rec = node.css('[data-section="recents"]')
    expect(fav.css('[data-row-type="model"]').map { |r| r["data-value"] }).to eq([ "m-2" ])
    expect(rec.css('[data-row-type="model"]').map { |r| r["data-value"] }).to eq([ "or-1" ])
  end

  it "renders no favorites/recents sections when the lists are empty" do
    node = render_picker
    expect(node.css('[data-section="favorites"]')).to be_empty
    expect(node.css('[data-section="recents"]')).to be_empty
  end

  it "shows the effort cycler only when the active provider declares reasoning" do
    none = render_picker # opencode → reasoning none
    expect(none.css('[data-row-type="effort"]')).to be_empty

    with = render_picker(active_provider: "openrouter", active_model: "or-1", effort: "high")
    row  = with.css('[data-row-type="effort"]').first
    expect(row).to be_present
    expect(row.text).to include("high")
  end

  it "shows 'model default' when effort is unset" do
    node = render_picker(active_provider: "openrouter", active_model: "or-1")
    expect(node.css('[data-row-type="effort"]').first.text).to include("model default")
  end

  it "keeps the header to title + Esc — no active-model summary (owner 2026-07-12)" do
    header = render_picker.css("#pito-ai-picker .font-bold").first.parent
    expect(header.text).not_to include("opencode/")
    expect(header.text).not_to include("no model selected")
  end

  it "never emits a value attribute on any password input" do
    node = render_picker
    expect(node.css("input[type=password]").map { |i| i["value"] }).to all(be_nil)
  end

  it "accepts no raw-key kwarg at all" do
    expect {
      described_class.new(providers:, active_provider: "opencode", api_key: "sk-leak")
    }.to raise_error(ArgumentError)
  end
end
