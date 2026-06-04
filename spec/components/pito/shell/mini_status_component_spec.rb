# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatusComponent do
  describe "rendered output" do
    context "mode: :connection (default)" do
      context "when state is true (authenticated)" do
        it "renders only the green disc ● without the 'auth' word" do
          node = render_inline(described_class.new(state: true))
          green_span = node.css("span.text-green").first
          expect(green_span).to be_present
          expect(green_span.text.strip).to eq("●")
        end

        it "does not render the 'auth' word when authenticated" do
          node = render_inline(described_class.new(state: true))
          expect(node.to_html).not_to include("auth")
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
          expect(node.css("span.text-green")).to be_empty
        end
      end
    end

    context "mode: :start" do
      it "renders only the auth label — no hints" do
        node = render_inline(described_class.new(mode: :start, state: false))
        expect(node.to_html).to include("○ auth")
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

      it "renders ○ auth in red when state: false" do
        node = render_inline(described_class.new(mode: :start, state: false))
        label = node.css("span.text-red").first
        expect(label).to be_present
        expect(label.text).to include("○ auth")
      end

      it "renders only ● in green when state: true (authenticated)" do
        node = render_inline(described_class.new(mode: :start, state: true))
        label = node.css("span.text-green").first
        expect(label).to be_present
        expect(label.text.strip).to eq("●")
        expect(node.to_html).not_to include("auth")
      end

      it "renders no separators in start mode" do
        node = render_inline(described_class.new(mode: :start, state: false))
        visible_faded = node.css("span.text-fg-faded").reject { |el|
          el.ancestors.any? { |a| a["class"]&.include?("hidden") }
        }
        expect(visible_faded).to be_empty
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
    end

    context "suggest hint (tab suggest)" do
      it "renders the suggest hint markup (initially hidden)" do
        node = render_inline(described_class.new)
        suggest_wrapper = node.css('[data-pito--mini-status-target="suggestHint"]').first
        expect(suggest_wrapper).to be_present
        expect(suggest_wrapper["class"]).to include("hidden")
      end

      it "includes 'tab' as the shortcut key in the suggest hint" do
        node = render_inline(described_class.new)
        suggest_wrapper = node.css('[data-pito--mini-status-target="suggestHint"]').first
        expect(suggest_wrapper.to_html).to include("tab")
      end

      it "includes 'suggest' as the label in the suggest hint" do
        node = render_inline(described_class.new)
        suggest_wrapper = node.css('[data-pito--mini-status-target="suggestHint"]').first
        expect(suggest_wrapper.to_html).to include("suggest")
      end
    end

    context "m chat hint" do
      it "renders the m-chat hint markup (initially hidden)" do
        node = render_inline(described_class.new)
        chat_wrapper = node.css('[data-pito--mini-status-target="chatHint"]').first
        expect(chat_wrapper).to be_present
        expect(chat_wrapper["class"]).to include("hidden")
      end

      it "includes 'm' as the shortcut key in the chat hint" do
        node = render_inline(described_class.new)
        chat_wrapper = node.css('[data-pito--mini-status-target="chatHint"]').first
        expect(chat_wrapper.to_html).to include(">m<")
      end

      it "includes 'chat' as the label in the chat hint" do
        node = render_inline(described_class.new)
        chat_wrapper = node.css('[data-pito--mini-status-target="chatHint"]').first
        expect(chat_wrapper.to_html).to include("chat")
      end
    end

    context "stimulus controller" do
      it "mounts pito--mini-status controller on the outer span" do
        node = render_inline(described_class.new)
        outer = node.css('[data-controller="pito--mini-status"]').first
        expect(outer).to be_present
      end
    end
  end
end
