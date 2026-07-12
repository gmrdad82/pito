# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatusComponent do
  describe "rendered output" do
    context "mode: :connection (default)" do
      context "when state is true (authenticated)" do
        it "renders the orange dot + the dim tag" do
          node = render_inline(described_class.new(state: true))
          dot = node.css("span#pito-conn-dot").first
          expect(dot["data-state"]).to eq("connecting")
          expect(dot.css("svg.pito-conn-icon--plug, svg.pito-conn-icon--cable")).not_to be_empty
          expect(node.text).to include("dev")
        end

        it "does not render the anonymous label" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).not_to include("tarnished")
        end
      end

      context "when state is false (anonymous)" do
        it "renders the red dot + red tarnished label" do
          node = render_inline(described_class.new(state: false))
          dot = node.css("span#pito-conn-dot").first
          expect(dot["class"]).to include("text-red")
          expect(dot.css("svg.pito-conn-icon--lock")).not_to be_empty
          expect(node.css("span.text-red").text).to include("tarnished")
        end

        it "does not render the authenticated label" do
          node = render_inline(described_class.new(state: false))
          expect(node.css("span.pito-me-shimmer")).to be_empty
        end
      end
    end

    context "mode: :start" do
      it "renders only the auth label — no hints" do
        node = render_inline(described_class.new(mode: :start, state: false))
        expect(node.text).to include("tarnished")
        expect(node.to_html).not_to include("ctrl+m")
        expect(node.to_html).not_to include("mute")
        expect(node.to_html).not_to include("tab")
        expect(node.to_html).not_to include("channels")
        expect(node.to_html).not_to include("shift+tab")
        expect(node.to_html).not_to include("period")
        expect(node.to_html).not_to include("ctrl+k")
        expect(node.to_html).not_to include("commands")
        expect(node.to_html).not_to include("suggest")
        expect(node.to_html).not_to include("chat")
      end

      it "renders tarnished in red when state: false" do
        node = render_inline(described_class.new(mode: :start, state: false))
        expect(node.css("span.text-red svg.pito-conn-icon--lock")).not_to be_empty
        expect(node.css("span.text-red").map(&:text).join).to include("tarnished")
      end

      it "renders the dot + tag when state: true (authenticated)" do
        node = render_inline(described_class.new(mode: :start, state: true))
        expect(node.text).to include("dev")
        expect(node.css("span#pito-conn-dot svg.pito-conn-icon--cable")).not_to be_empty
      end

      it "renders no separators in start mode" do
        node = render_inline(described_class.new(mode: :start, state: false))
        visible_faded = node.css("span.text-fg-faded").reject { |el|
          el.ancestors.any? { |a| a["class"]&.include?("hidden") }
        }
        expect(visible_faded).to be_empty
      end

      it "renders ctrl+k when authenticated and in start mode" do
        node = render_inline(described_class.new(mode: :start, state: true))
        yellow_bold = node.css("span.font-bold.text-yellow")
        expect(yellow_bold.map(&:text)).to include("ctrl+k")
      end

      it "does NOT render ctrl+k when unauthenticated and in start mode" do
        node = render_inline(described_class.new(mode: :start, state: false))
        expect(node.to_html).not_to include("ctrl+k")
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

      it "renders notifications as ctrl+/ (yellow) + a muted count (item 7)" do
        node = render_inline(described_class.new(notifications: 2, show_notifications: true))
        yellow = node.css("span.font-bold.text-yellow")
        expect(yellow.map(&:text)).to include("ctrl+/")
        expect(node.text).to include("2")
          expect(node.to_html).to include("M10.268 21a2 2 0 0 0 3.464 0") # the bell
        expect(node.css('[role="button"]')).to be_empty
      end

      it "renders the count with the '*' glyph (singular)" do
        node = render_inline(described_class.new(notifications: 1, show_notifications: true))
        expect(node.to_html).to include("1")
      end

      it "renders the count with the bell glyph (plural)" do
        node = render_inline(described_class.new(notifications: 3, show_notifications: true))
        expect(node.text).to include("3")
        expect(node.to_html).to include("M10.268 21a2 2 0 0 0 3.464 0") # the bell
      end

      it "does NOT render notifications when unauthenticated (state: false)" do
        node = render_inline(described_class.new(notifications: 3, show_notifications: true, state: false))
        expect(node.to_html).not_to include("notifications")
        expect(node.css("span.font-bold.text-yellow").map(&:text)).not_to include("ctrl+/")
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

      it "does not render the audio/mute hint (ctrl+m removed)" do
        node = render_inline(described_class.new)
        expect(node.to_html).not_to include("ctrl+m")
        expect(node.to_html).not_to include("mute")
        expect(node.css("span#pito-audio-label").first).to be_nil
      end

      it "does not render the channel/period keybind hints (moved to filter row)" do
        node = render_inline(described_class.new)
        html = node.to_html
        expect(html).not_to include("shift+tab")
        expect(html).not_to include("channels")
        expect(html).not_to include("shift+space")
      end

      it "does not render suggest or chat hints (moved to chatbox filter row)" do
        node = render_inline(described_class.new)
        html = node.to_html
        expect(html).not_to include("suggest")
        expect(html).not_to include(">chat<")
      end
    end

    context "no Stimulus controller on the outer span" do
      it "does not mount pito--mini-status controller on the outer span" do
        node = render_inline(described_class.new)
        outer = node.css('[data-controller="pito--mini-status"]').first
        expect(outer).to be_nil
      end
    end
  end
end
