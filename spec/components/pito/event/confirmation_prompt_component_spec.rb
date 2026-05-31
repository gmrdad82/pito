# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationPromptComponent do
  let(:payload) do
    {
      prompt_key: "pito.slash.confirm_demo.prompt",
      command_text: "/confirm_demo"
    }
  end

  describe "#initialize" do
    it "resolves the prompt via I18n" do
      comp = described_class.new(payload: payload)
      node = render_inline(comp)
      expect(node.css("span.text-fg").first.text).to include("Confirm running this demo command?")
    end

    it "stores command_text as a string" do
      comp = described_class.new(payload: payload)
      node = render_inline(comp)
      expect(node.css("span.text-cyan").text).to include("/confirm_demo")
    end

    it "coerces nil command_text to an empty string" do
      comp = described_class.new(payload: { prompt_key: "pito.slash.confirm_demo.prompt" })
      node = render_inline(comp)
      expect(node.css("span.text-cyan").text.strip).to eq("")
    end

    it "interpolates prompt_args into the translation" do
      comp = described_class.new(
        payload: {
          prompt_key: "pito.slash.help.entry",
          prompt_args: { verb: "test", description: "Test cmd" },
          command_text: ""
        }
      )
      node = render_inline(comp)
      expect(node.css("span.text-fg").first.text).to include("/test")
      expect(node.css("span.text-fg").first.text).to include("Test cmd")
    end
  end

  describe "rendered output" do
    subject(:node) { render_inline(described_class.new(payload: payload)) }

    it "renders the prompt text in span.text-fg" do
      expect(node.css("span.text-fg").first.text).to include("Confirm running this demo command?")
    end

    it "renders the command text in span.text-cyan" do
      expect(node.css("span.text-cyan").text).to include("/confirm_demo")
    end

    it "renders the confirm hint text" do
      # pito.slash.confirm_hint => "type /confirm or /cancel"
      hint_span = node.css("span.text-fg-dim")
      expect(hint_span.text).to include("/confirm")
      expect(hint_span.text).to include("/cancel")
    end

    it "renders an accent border bar (yellow border passed to Segment)" do
      bar = node.css("div[style*='width: 4px']").first
      expect(bar).not_to be_nil
      expect(bar["style"]).to include("var(--accent-yellow)")
    end

    it "wraps content in a flex column container" do
      expect(node.css("div.flex.flex-col").first).not_to be_nil
    end
  end
end
