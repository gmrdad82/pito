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
    # The span goes through ShortcutComponent, so the DISPLAY is glyphed while
    # the kbd-click key value stays the raw label the handler table is keyed on
    # — the two must never be conflated (a glyphed key value would kill tap).
    {
      "ctrl+/"     => "ctrl+/",
      "ctrl+space" => "ctrl+space",
      "shift+up"   => "shift+↑"
    }.each do |raw, glyphed|
      it "renders #{raw} as the glyph token #{glyphed} while keeping the raw key value" do
        node     = render_inline(described_class.new(suggestion: { code: "/x", shortcut: raw, run_cmd: "/x" }))
        shortcut = node.css("span.pito-kbd-shimmer").first

        expect(shortcut).to be_present
        expect(shortcut.text).to eq(glyphed)
        expect(shortcut["data-pito--kbd-click-key-value"]).to eq(raw)
      end
    end

    it "wires the kbd-click controller so a tap fires the key" do
      shortcut = node.css("span.pito-kbd-shimmer").first
      expect(shortcut["data-controller"]).to include("pito--kbd-click")
      expect(shortcut["data-action"]).to include("pito--kbd-click#fire")
    end

    it "passes an unparseable shortcut through unchanged rather than mangling it" do
      node = render_inline(described_class.new(suggestion: { code: "/x", shortcut: "any key", run_cmd: "/x" }))
      expect(node.css("span.pito-kbd-shimmer").first.text).to eq("any key")
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
