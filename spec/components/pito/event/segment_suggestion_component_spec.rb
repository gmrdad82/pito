# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::SegmentSuggestionComponent do
  let(:suggestion) do
    {
      pre:       "Run",
      code:      "/connect",
      post:      "after configuring to start the OAuth2 flow",
      shortcut:  "ctrl+/",
      run_label: "run this",
      run_cmd:   "/connect"
    }
  end

  subject(:node) { render_inline(described_class.new(suggestion:)) }

  describe "suggestion-command data attribute" do
    it "sets data-suggestion-command on the wrapper" do
      wrapper = node.css("[data-suggestion-command]").first
      expect(wrapper).to be_present
      expect(wrapper["data-suggestion-command"]).to eq("/connect")
    end
  end

  describe "inline code" do
    it "renders the code span with elevated background" do
      code_span = node.css("span.bg-elevated").first
      expect(code_span).to be_present
      expect(code_span.text.strip).to eq("/connect")
    end
  end

  describe "pre and post text" do
    it "renders pre text as muted" do
      expect(node.css("span.text-fg-dim").map(&:text)).to include("Run")
    end

    it "renders post text as muted" do
      expect(node.text).to include("after configuring to start the OAuth2 flow")
    end
  end

  describe "keyboard shortcut" do
    it "renders ctrl+/ as a kbd-shimmer token" do
      shortcut = node.css("span.pito-kbd-shimmer").first
      expect(shortcut).to be_present
      expect(shortcut.text).to eq("ctrl+/")
    end

    it "renders the run label" do
      expect(node.text).to include("run this")
    end
  end

  describe "separator" do
    it "renders a top border separator" do
      wrapper = node.css("[data-suggestion-command]").first
      expect(wrapper["class"]).to include("border-t")
    end
  end

  describe "empty optional fields" do
    it "renders with only code and run_cmd" do
      node = render_inline(described_class.new(suggestion: { code: "/help", run_cmd: "/help" }))
      expect(node.css("[data-suggestion-command]").first["data-suggestion-command"]).to eq("/help")
      expect(node.text).to include("/help")
    end
  end
end
