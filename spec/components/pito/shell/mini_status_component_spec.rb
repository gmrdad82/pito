# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatusComponent do
  # connection_label uses `t(...)` which requires a render context — tested via render_inline below.
  # connection_class is a pure Ruby method and can be called directly.
  describe "#connection_class" do
    it "returns text-green when state is true" do
      comp = described_class.new(state: true)
      expect(comp.connection_class).to eq("text-green")
    end

    it "returns text-red when state is false" do
      comp = described_class.new(state: false)
      expect(comp.connection_class).to eq("text-red")
    end
  end

  describe "rendered output" do
    context "mode: :connection (default)" do
      context "when state is true (authenticated)" do
        it "renders the green ● auth label" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).to include("● auth")
          expect(node.css("span.text-green").text).to include("● auth")
        end

        it "does not render the anonymous label" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).not_to include("○ auth")
        end
      end

      context "when state is false (anonymous)" do
        it "renders the red ○ auth label" do
          node = render_inline(described_class.new(state: false))
          expect(node.to_html).to include("○ auth")
          expect(node.css("span.text-red").text).to include("○ auth")
        end

        it "does not render the authenticated label" do
          node = render_inline(described_class.new(state: false))
          expect(node.to_html).not_to include("● auth")
        end
      end
    end

    context "mode: :start" do
      it "renders only the ○ auth label" do
        node = render_inline(described_class.new(mode: :start))
        expect(node.to_html).to include("○ auth")
        expect(node.to_html).not_to include("tab")
        expect(node.to_html).not_to include("channels")
        expect(node.to_html).not_to include("shift+tab")
        expect(node.to_html).not_to include("period")
        expect(node.to_html).not_to include("ctrl+k")
        expect(node.to_html).not_to include("commands")
      end

      it "does not render · separators when in start mode" do
        node = render_inline(described_class.new(mode: :start))
        expect(node.css("span.text-fg-faded")).to be_empty
      end
    end

    context "notifications" do
      it "does not render notification count when show_notifications is false" do
        node = render_inline(described_class.new(notifications: 5, show_notifications: false))
        expect(node.to_html).not_to include("(")
      end

      it "does not render notification count when notifications is 0 and show_notifications is true" do
        node = render_inline(described_class.new(notifications: 0, show_notifications: true))
        expect(node.to_html).not_to include("(")
      end

      it "renders notification count in cyan parentheses" do
        node = render_inline(described_class.new(notifications: 2, show_notifications: true))
        cyan_text = node.css("span.text-cyan").map(&:text).join
        expect(cyan_text).to eq("(2)")
      end

      it "renders singular count" do
        node = render_inline(described_class.new(notifications: 1, show_notifications: true))
        expect(node.to_html).to include("(1)")
      end

      it "renders plural count" do
        node = render_inline(described_class.new(notifications: 3, show_notifications: true))
        expect(node.to_html).to include("(3)")
      end
    end

    context "always-present elements (connection mode only)" do
      it "renders the commands hint ('ctrl+k') in a bold yellow span" do
        node = render_inline(described_class.new)
        yellow_bold = node.css("span.font-bold.text-yellow")
        expect(yellow_bold.map(&:text)).to include("ctrl+k")
      end

      it "renders the 'commands' label in a dim span" do
        node = render_inline(described_class.new)
        dim_text = node.css("span.text-fg-dim").map(&:text).join
        expect(dim_text).to include("commands")
      end

      it "renders separator dots in faded spans" do
        node = render_inline(described_class.new)
        faded_texts = node.css("span.text-fg-faded").map(&:text)
        expect(faded_texts).to include("·")
      end
    end
  end
end
