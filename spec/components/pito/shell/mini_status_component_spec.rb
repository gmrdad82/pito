# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatusComponent do
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
      it "renders only the auth label — no audio hint" do
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
      end

      it "renders ○ auth in red when state: false" do
        node = render_inline(described_class.new(mode: :start, state: false))
        label = node.css("span.text-red").first
        expect(label).to be_present
        expect(label.text).to include("○ auth")
      end

      it "renders ● auth in green when state: true (authenticated)" do
        node = render_inline(described_class.new(mode: :start, state: true))
        label = node.css("span.text-green").first
        expect(label).to be_present
        expect(label.text).to include("● auth")
      end

      it "renders no separators in start mode" do
        node = render_inline(described_class.new(mode: :start, state: false))
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

      it "renders the audio hint ('ctrl+m') in a bold yellow span" do
        node = render_inline(described_class.new)
        yellow_bold = node.css("span.font-bold.text-yellow")
        expect(yellow_bold.map(&:text)).to include("ctrl+m")
      end

      it "renders the 'mute' label in a dim span with the toggle id" do
        node = render_inline(described_class.new)
        label = node.css("span#pito-audio-label").first
        expect(label).not_to be_nil
        expect(label.text).to include("mute")
        expect(label["class"]).to include("text-fg-dim")
      end

      it "places ctrl+m before ctrl+k" do
        node = render_inline(described_class.new)
        html = node.to_html
        ctrl_m_pos = html.index("ctrl+m")
        ctrl_k_pos = html.index("ctrl+k")
        expect(ctrl_m_pos).to be < ctrl_k_pos
      end
    end
  end
end
