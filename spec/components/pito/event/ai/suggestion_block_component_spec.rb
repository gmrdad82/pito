# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::Ai::SuggestionBlockComponent, type: :component do
  subject(:node) { render_inline(described_class.new(command: "list games", note: "worth a look")) }

  it "renders the >-prefixed command line" do
    expect(node.css("span.text-fg-faded").text).to eq(">")
    expect(node.text).to include("list games")
  end

  it "renders the note in dim text" do
    expect(node.css("div.text-fg-dim").text).to include("worth a look")
  end

  it "omits the note line when absent" do
    node = render_inline(described_class.new(command: "list games"))
    expect(node.css("div.text-fg-dim")).to be_empty
  end

  it "renders the use widget with ONLY the copy button (no stage icon)" do
    expect(node.at_css(".pito-copy[data-controller='pito--clipboard']")).to be_present
    expect(node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")).to be_present
    expect(node.css(".pito-copy__btn").size).to eq(1)
  end

  it "renders the shift+u accept chip (kbd-shimmer band) beside the command" do
    kbd = node.at_css("span.pito-kbd-shimmer")
    expect(kbd).not_to be_nil
    expect(kbd.text).to eq("shift+u")
  end

  it "renders the copy-driven 'to accept' hint text next to the chip" do
    chip = node.at_css("[data-pito-use-widget-fill]")
    expect(chip.text.strip).to eq("shift+u to accept")
  end

  it "carries the data-pito-use-widget-fill marker + pito--chat-prefill wiring on the chip, staged with THIS line's command" do
    chip = node.at_css("[data-pito-use-widget-fill]")
    expect(chip).to be_present
    expect(chip["data-controller"]).to eq("pito--chat-prefill")
    expect(chip["data-action"]).to eq("click->pito--chat-prefill#fill")
    expect(chip["data-pito--chat-prefill-text-value"]).to eq("list games")
  end

  it "is stage-only — no submit value on the chip (never auto-submits)" do
    chip = node.at_css("[data-pito-use-widget-fill]")
    expect(chip["data-pito--chat-prefill-submit-value"]).to be_nil
  end

  it "renders exactly one marker element (the chip, not the copy button)" do
    expect(node.css("[data-pito-use-widget-fill]").size).to eq(1)
  end

  it "stages the exact command text, not the note" do
    chip = node.at_css("[data-pito-use-widget-fill]")
    expect(chip["data-pito--chat-prefill-text-value"]).to eq("list games")
  end
end
