# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::Ai::SuggestionBlockComponent, type: :component do
  subject(:node) { render_inline(described_class.new(command: "list games", note: "worth a look")) }

  it "renders the >-prefixed command line" do
    expect(node.css("span.text-fg-faded").text).to eq(">")
    expect(node.text).to include("list games")
  end

  it "renders the note in dim text" do
    expect(node.css(".text-fg-dim").text).to include("worth a look")
  end

  it "omits the note line when absent" do
    node = render_inline(described_class.new(command: "list games"))
    expect(node.css(".text-fg-dim")).to be_empty
  end

  it "renders the use widget with BOTH the copy button and the stage-in-chatbox fill button" do
    expect(node.at_css(".pito-copy[data-controller='pito--clipboard']")).to be_present
    expect(node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")).to be_present

    fill_btn = node.at_css("button[data-pito-use-widget-fill]")
    expect(fill_btn).to be_present
    expect(fill_btn["data-controller"]).to eq("pito--chat-prefill")
    expect(fill_btn["data-pito--chat-prefill-text-value"]).to eq("list games")
    expect(fill_btn["data-action"]).to eq("click->pito--clipboard#copy click->pito--chat-prefill#fill")
  end

  it "stages the exact command text, not the note" do
    fill_btn = node.at_css("button[data-pito-use-widget-fill]")
    expect(fill_btn["data-pito--chat-prefill-text-value"]).to eq("list games")
  end
end
