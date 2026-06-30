# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::InProgressComponent do
  describe "rendered output" do
    context "with a valid i18n verb key" do
      it "renders the translated verb text" do
        # Use the chatbox placeholder as a real, existing i18n key to get a translated string
        # pito.shell.chatbox.placeholder = "Type a command or message…"
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        expect(node.to_html).to include("Type a command or message")
      end

      it "renders a span with the shimmer class for the verb text" do
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        shimmer_spans = node.css("span.pito-network-shimmer")
        expect(shimmer_spans.length).to be >= 2
      end

      it "renders the braille spinner character in a shimmer span" do
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        # The spinner glyph is the first pito-network-shimmer span
        first_shimmer = node.css("span.pito-network-shimmer").first
        expect(first_shimmer.text).to include("⠋")
      end

      it "renders the ellipsis separator in a faded span" do
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        faded = node.css("span.text-fg-faded")
        expect(faded.map(&:text)).to include("…")
      end
    end

    context "with an authenticated label key" do
      it "renders the auth indicator text" do
        node = render_inline(described_class.new(verb_key: "pito.shell.mini_status.authenticated"))
        expect(node.to_html).to include("■")
      end
    end

    context "structural checks" do
      it "uses the pito-network-shimmer class on shimmer spans" do
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        expect(node.css("span.pito-network-shimmer").length).to be >= 2
      end

      it "renders the outer span wrapper" do
        node = render_inline(described_class.new(verb_key: "pito.shell.chatbox.placeholder"))
        expect(node.css("span")).not_to be_empty
      end
    end
  end
end
