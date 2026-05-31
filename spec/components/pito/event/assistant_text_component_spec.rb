# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::AssistantTextComponent do
  describe "#initialize / resolve_text" do
    context "when payload has :text" do
      it "uses the text value directly" do
        comp = described_class.new(payload: { text: "Hello world" })
        node = render_inline(comp)
        expect(node.css("span.text-fg").text).to include("Hello world")
      end
    end

    context "when payload has :message_key" do
      it "resolves the key via I18n" do
        comp = described_class.new(payload: { message_key: "pito.event.thought.prefix" })
        node = render_inline(comp)
        expect(node.css("span.text-fg").text).to include("Thought")
      end

      it "interpolates message_args into the translation" do
        comp = described_class.new(
          payload: {
            message_key: "pito.slash.errors.unknown_verb",
            message_args: { verb: "foo" }
          }
        )
        node = render_inline(comp)
        expect(node.css("span.text-fg").text).to include("foo")
      end
    end

    context "when payload is empty" do
      it "renders the segment wrapper without a text span body" do
        node = render_inline(described_class.new(payload: {}))
        # @body is nil — template falls through to `content` block (empty)
        expect(node.css("span.text-fg")).to be_empty
      end
    end

    context "when body: is passed directly (legacy path)" do
      it "uses the explicit body, ignoring payload" do
        comp = described_class.new(body: "Legacy body", payload: { text: "ignored" })
        node = render_inline(comp)
        expect(node.css("span.text-fg").text).to include("Legacy body")
        expect(node.css("span.text-fg").text).not_to include("ignored")
      end
    end
  end

  describe "rendered output" do
    it "wraps content inside the segment flex container" do
      node = render_inline(described_class.new(payload: { text: "Rendered" }))
      expect(node.css("div.flex").first).not_to be_nil
    end

    it "renders the text inside a span.text-fg" do
      node = render_inline(described_class.new(payload: { text: "Check span" }))
      expect(node.css("span.text-fg").text.strip).to eq("Check span")
    end

    it "does not render an accent border bar (no border arg passed to Segment)" do
      node = render_inline(described_class.new(payload: { text: "No border" }))
      # Segment without border renders no 4px bar div
      bar_divs = node.css("div[style*='width: 4px']")
      expect(bar_divs).to be_empty
    end
  end
end
