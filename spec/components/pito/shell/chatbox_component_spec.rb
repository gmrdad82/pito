# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ChatboxComponent do
  describe "rendered output" do
    context "without a placeholder_key" do
      it "renders the chatbox-wrapper div" do
        node = render_inline(described_class.new)
        expect(node.css("div.chatbox-wrapper")).not_to be_empty
      end

      it "renders the textarea with the sampled auth hint (unauthenticated → login)" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea")
        expect(textarea).not_to be_empty
        expect(textarea.first["placeholder"]).to include("/login")
      end
    end

    context "with a placeholder_key" do
      it "renders the textarea with the translated placeholder" do
        node = render_inline(described_class.new(placeholder_key: "pito.shell.chatbox.placeholder"))
        textarea = node.css("textarea")
        expect(textarea.first["placeholder"]).to include("Type a command or message")
      end
    end

    context "filter line (line 2)" do
      it "shows channel and period labels when filter is given and state is :default" do
        node = render_inline(described_class.new(
          filter: { channel: "gaming", period: "last 7d" }
        ))
        html = node.to_html
        expect(html).to include("channel")
        expect(html).to include("period")
        expect(html).to include("gaming")
        expect(html).to include("last 7d")
      end

      it "renders channel and period values inside .text-cyan spans" do
        node = render_inline(described_class.new(
          filter: { channel: "sports", period: "30d" }
        ))
        cyan_texts = node.css("span.text-cyan").map(&:text)
        expect(cyan_texts).to include("sports")
        expect(cyan_texts).to include("30d")
      end

      it "uses mx-2 spacing for the separator dot (matches mini status bar)" do
        node = render_inline(described_class.new(
          filter: { channel: "gaming", period: "7d" }
        ))
        dot_spans = node.css("span.mx-2").select { |s| s.text.strip == "·" }
        expect(dot_spans).not_to be_empty
      end

      it "uses ml-2 spacing for channel and period values (matches mini status bar)" do
        node = render_inline(described_class.new(
          filter: { channel: "gaming", period: "7d" }
        ))
        cyan_spans = node.css("span.text-cyan")
        expect(cyan_spans.first["class"]).to include("ml-2")
      end

      it "does NOT render the filter line when state is :start" do
        node = render_inline(described_class.new(
          state: :start,
          filter: { channel: "gaming", period: "7d" }
        ))
        html = node.to_html
        expect(html).not_to include("Channel")
        expect(html).not_to include("gaming")
      end

      it "does NOT render the filter line when filter is nil" do
        node = render_inline(described_class.new(filter: nil))
        expect(node.css("span.text-cyan")).to be_empty
      end
    end

    context "input_data attributes" do
      it "merges custom data attributes onto the textarea" do
        node = render_inline(described_class.new(
          input_data: { pito__chat_form_target: "inputField" }
        ))
        textarea = node.css("textarea").first
        # data attributes are hyphenated in HTML
        expect(textarea["data-pito--chat-form-target"]).to eq("inputField")
      end
    end

    context "structural checks" do
      it "renders a flex column wrapper for the two-line layout" do
        node = render_inline(described_class.new)
        expect(node.css("div.flex.flex-col")).not_to be_empty
      end

      it "renders the field-wrap div with the terminal-caret Stimulus controller" do
        node = render_inline(described_class.new)
        field_wrap = node.css("div.pito-chatbox__field-wrap").first
        expect(field_wrap).not_to be_nil
        expect(field_wrap["data-controller"]).to eq("pito--terminal-caret")
      end

      it "renders the textarea with the terminal-caret field target" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea[data-pito--terminal-caret-target='field']").first
        expect(textarea).not_to be_nil
      end

      it "renders the terminal-caret span with the block target" do
        node = render_inline(described_class.new)
        caret = node.css("span.terminal-caret[data-pito--terminal-caret-target='block']").first
        expect(caret).not_to be_nil
      end

      it "does not render a pito-cursor span in the chatbox" do
        node = render_inline(described_class.new)
        expect(node.css("span.pito-cursor")).to be_empty
      end
    end
  end
end
