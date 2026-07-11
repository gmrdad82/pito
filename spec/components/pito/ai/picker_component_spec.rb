# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Ai::PickerComponent, type: :component do
  let(:models) do
    [
      { id: "a-1", pinned: false },
      { id: "b-2", pinned: true }
    ]
  end

  def build(key_present:, active_model: "a-1")
    described_class.new(
      provider: :opencode,
      label: "OpenCode Zen",
      models: models,
      active_model: active_model,
      key_present: key_present
    )
  end

  describe "no key present" do
    subject(:node) { render_inline(build(key_present: false)) }

    it "shows the key entry section (not hidden)" do
      key_section = node.css("[data-pito--ai-picker-target='keySection']").first
      expect(key_section).to be_present
      expect(key_section.key?("hidden")).to be false
    end

    it "hides the models section" do
      models_section = node.css("[data-pito--ai-picker-target='modelsSection']").first
      expect(models_section).to be_present
      expect(models_section.key?("hidden")).to be true
    end

    it "shows the no-key chip" do
      chip = node.css("[data-pito--ai-picker-target='keyChip']").first
      expect(chip.text).to include("no key")
    end
  end

  describe "key present" do
    subject(:node) { render_inline(build(key_present: true)) }

    it "hides the key entry section" do
      key_section = node.css("[data-pito--ai-picker-target='keySection']").first
      expect(key_section).to be_present
      expect(key_section.key?("hidden")).to be true
    end

    it "shows the models section (not hidden)" do
      models_section = node.css("[data-pito--ai-picker-target='modelsSection']").first
      expect(models_section).to be_present
      expect(models_section.key?("hidden")).to be false
    end

    it "shows the masked key chip" do
      chip = node.css("[data-pito--ai-picker-target='keyChip']").first
      expect(chip.text).to include("●●●●")
    end
  end

  describe "model rows" do
    subject(:node) { render_inline(build(key_present: true)) }

    it "renders one row per model entry" do
      rows = node.css("[data-pito--ai-picker-target='row']")
      expect(rows.length).to eq(2)
    end

    it "attaches data-value with the model id to each row" do
      rows = node.css("[data-pito--ai-picker-target='row']")
      expect(rows.map { |r| r["data-value"] }).to eq(%w[a-1 b-2])
    end

    it "marks only the active model's row with the bullet marker" do
      rows = node.css("[data-pito--ai-picker-target='row']")
      expect(rows[0].text).to include("●")
      expect(rows[1].text).not_to include("●")
    end

    it "shows the pinned badge only on the pinned entry" do
      rows = node.css("[data-pito--ai-picker-target='row']")
      expect(rows[0].text).not_to include("pinned")
      expect(rows[1].text).to include("pinned")
    end
  end

  describe "root attributes" do
    subject(:node) { render_inline(build(key_present: false)) }

    it "gives the root node the id pito-ai-picker" do
      expect(node.css("#pito-ai-picker")).not_to be_empty
    end

    it "passes the settings endpoint as a data value" do
      root = node.css("#pito-ai-picker").first
      expect(root["data-pito--ai-picker-endpoint-value"]).to eq("/settings/ai")
    end

    it "passes the provider as a data value" do
      root = node.css("#pito-ai-picker").first
      expect(root["data-pito--ai-picker-provider-value"]).to eq("opencode")
    end
  end

  describe "no raw API key ever appears in the markup" do
    it "never emits a value attribute on the password input, for any key_present state" do
      [ true, false ].each do |present|
        node     = render_inline(build(key_present: present))
        pw_input = node.css("input[type='password']").first
        expect(pw_input["value"]).to be_nil
      end
    end

    it "has no keyword for injecting a raw key value into the component" do
      expect do
        described_class.new(provider: :opencode, label: "OpenCode Zen", models: models, api_key: "sk-should-not-exist")
      end.to raise_error(ArgumentError)
    end

    it "shows only the masked glyph in the key chip, never a literal value attribute" do
      node = render_inline(build(key_present: true))
      chip = node.css("[data-pito--ai-picker-target='keyChip']").first
      expect(chip.text).to include("●●●●")
      expect(chip.to_html).not_to match(/value=/)
    end
  end
end
