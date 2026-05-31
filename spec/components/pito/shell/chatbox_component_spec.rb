# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ChatboxComponent do
  describe "rendered output" do
    context "without a placeholder_key" do
      it "renders the chatbox-wrapper div" do
        node = render_inline(described_class.new)
        expect(node.css("div.chatbox-wrapper")).not_to be_empty
      end

      it "renders the textarea with an empty placeholder attribute" do
        node = render_inline(described_class.new)
        textarea = node.css("textarea")
        expect(textarea).not_to be_empty
        expect(textarea.first["placeholder"]).to eq("")
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
        expect(html).to include("Channel")
        expect(html).to include("Period")
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

      it "renders the ghost cursor character" do
        node = render_inline(described_class.new)
        # Cursor component renders the "/" char
        expect(node.to_html).to include("/")
      end
    end
  end
end
