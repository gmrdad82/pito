# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Footage::SnippetComponent do
  subject(:node) { render_inline(described_class.new) }

  it "renders the exact ffprobe one-liner command in the code block" do
    code = node.css(".pito-footage-snippet__code").first

    expect(code).not_to be_nil
    expect(code.text).to eq(described_class::COMMAND)
  end

  it "exposes the command with the half-hour ceil and 1-decimal total math" do
    expect(described_class::COMMAND).to include("-maxdepth 1")
    expect(described_class::COMMAND).to include("int(($1+1799)/1800)")
    expect(described_class::COMMAND).to include("s/2")
    expect(described_class::COMMAND).to include("wl-copy")
  end

  it "wires the root to the pito--clipboard controller with the command as text-value" do
    root = node.css("[data-controller='pito--clipboard']").first

    expect(root).not_to be_nil
    expect(root["data-pito--clipboard-text-value"]).to eq(described_class::COMMAND)
  end

  it "renders a copy affordance with the click->copy action" do
    button = node.css("button[data-action='click->pito--clipboard#copy']").first

    expect(button).not_to be_nil
    expect(button["aria-label"]).to be_present
  end

  it "renders the clipboard feedback target" do
    feedback = node.css("[data-pito--clipboard-target='feedback']").first

    expect(feedback).not_to be_nil
    expect(feedback.text).to eq("Copy")
  end

  it "leads with the inline timestamp slot so the message timestamp lands on the first line" do
    expect(node.css("[data-pito-ts-slot]")).not_to be_empty
  end

  it "renders the dim hint pointing at footage update" do
    hint = node.css(".pito-footage-snippet__hint").first

    expect(hint).not_to be_nil
    expect(hint.text).to include("footage update <id> <hours>")
  end
end
