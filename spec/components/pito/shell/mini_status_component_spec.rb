# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatusComponent do
  # connection_label uses `t(...)` which requires a render context — tested via render_inline below.
  # connection_color is a pure Ruby method and can be called directly.
  describe "#connection_color" do
    it "returns the green accent variable when state is true" do
      comp = described_class.new(state: true)
      expect(comp.connection_color).to eq("var(--accent-green)")
    end

    it "returns the red accent variable when state is false" do
      comp = described_class.new(state: false)
      expect(comp.connection_color).to eq("var(--accent-red)")
    end
  end

  describe "rendered output" do
    context "mode: :connection (default)" do
      context "when state is true (authenticated)" do
        it "renders the 'Authenticated' label" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).to include("Authenticated")
        end

        it "does not render 'Anonymous'" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).not_to include("Anonymous")
        end

        it "renders the label inside a span element" do
          node = render_inline(described_class.new(state: true))
          span_texts = node.css("span").map(&:text)
          expect(span_texts).to include("Authenticated")
        end
      end

      context "when state is false (anonymous)" do
        it "renders the 'Anonymous' label" do
          node = render_inline(described_class.new(state: false))
          expect(node.to_html).to include("Anonymous")
        end

        it "does not render 'Authenticated'" do
          node = render_inline(described_class.new(state: false))
          expect(node.to_html).not_to include("Authenticated")
        end
      end
    end

    context "mode: :start" do
      it "renders the not_authenticated label ('Anonymous')" do
        node = render_inline(described_class.new(mode: :start))
        # pito.shell.mini_status.not_authenticated = "Anonymous"
        expect(node.to_html).to include("Anonymous")
      end

      it "does not use connection_label in start mode" do
        # In :start mode the template renders t("...not_authenticated") directly,
        # skipping the connection_label method; state:true should not produce "Authenticated"
        node = render_inline(described_class.new(mode: :start, state: true))
        expect(node.to_html).not_to include("Authenticated")
      end
    end

    context "notifications" do
      it "does not render notification count when show_notifications is false" do
        node = render_inline(described_class.new(notifications: 5, show_notifications: false))
        expect(node.to_html).not_to include("notification")
      end

      it "does not render notification count when notifications is 0 and show_notifications is true" do
        node = render_inline(described_class.new(notifications: 0, show_notifications: true))
        expect(node.to_html).not_to include("notification")
      end

      it "renders singular notification count when count is 1" do
        node = render_inline(described_class.new(notifications: 1, show_notifications: true))
        expect(node.to_html).to include("1 notification")
      end

      it "renders plural notification count when count is greater than 1" do
        node = render_inline(described_class.new(notifications: 3, show_notifications: true))
        expect(node.to_html).to include("3 notifications")
      end

      it "renders the notification count in a .text-cyan span" do
        node = render_inline(described_class.new(notifications: 2, show_notifications: true))
        cyan_text = node.css("span.text-cyan").map(&:text).join
        expect(cyan_text).to include("2 notifications")
      end
    end

    context "always-present elements" do
      it "renders the commands hint ('/') in a bold yellow span" do
        node = render_inline(described_class.new)
        yellow_bold = node.css("span.font-bold.text-yellow")
        expect(yellow_bold.map(&:text)).to include("/")
      end

      it "renders the 'for commands' label in a dim span" do
        node = render_inline(described_class.new)
        dim_text = node.css("span.text-fg-dim").map(&:text).join
        expect(dim_text).to include("for commands")
      end

      it "renders a separator dot in a faded span" do
        node = render_inline(described_class.new)
        faded_texts = node.css("span.text-fg-faded").map(&:text)
        expect(faded_texts).to include("·")
      end
    end
  end
end
