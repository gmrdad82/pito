# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::ContextMeterComponent, type: :component do
  subject(:component) { described_class.new(event_count: event_count) }
  let(:event_count) { 0 }

  describe "#fill_pct" do
    it "is 0% when event_count is 0" do
      expect(component.fill_pct).to eq(0.0)
    end

    it "is 50% when event_count is 50" do
      expect(described_class.new(event_count: 50).fill_pct).to eq(50.0)
    end

    it "is 100% when event_count is 100" do
      expect(described_class.new(event_count: 100).fill_pct).to eq(100.0)
    end

    it "pegs at 100% when event_count exceeds THRESHOLD" do
      expect(described_class.new(event_count: 200).fill_pct).to eq(100.0)
    end
  end

  describe "#full?" do
    it "is false below threshold" do
      expect(described_class.new(event_count: 99).full?).to be(false)
    end

    it "is true at threshold" do
      expect(described_class.new(event_count: 100).full?).to be(true)
    end
  end

  describe "rendered HTML" do
    subject(:node) { render_inline(component) }

    it "renders the stable DOM id" do
      expect(node.css("#pito-context-meter")).not_to be_empty
    end

    it "renders the counter text" do
      expect(node.text).to include("0%")
    end

    # CTXF2 / 13.39: the header (holding the counter) sits ABOVE the track.
    it "renders the header (with counter) before the track in DOM order" do
      meter = node.css("#pito-context-meter").first
      children = meter.children.select(&:element?)
      header = children.find { |c| c["class"]&.include?("pito-context-meter__header") }
      track  = children.find { |c| c["class"]&.include?("pito-context-meter__track") }
      expect(children.index(header)).to be < children.index(track)
      expect(header.css(".pito-context-meter__counter")).not_to be_empty
    end

    # 13.39 / Q3: conversation name at the LEFT of the header, only when named.
    it "renders the conversation name on the left when present" do
      named = render_inline(described_class.new(event_count: 5, conversation_name: "My Chat"))
      expect(named.css(".pito-context-meter__name").text).to eq("My Chat")
    end

    it "renders no name span when the conversation is unnamed (nil/blank)" do
      expect(render_inline(described_class.new(event_count: 5)).css(".pito-context-meter__name")).to be_empty
      expect(render_inline(described_class.new(event_count: 5, conversation_name: "  ")).css(".pito-context-meter__name")).to be_empty
    end

    context "when at 50 events" do
      let(:event_count) { 50 }

      it "shows 50% counter" do
        expect(node.text).to include("50%")
      end

      # CTXF3: fill is a clip window; gradient lives on the inner gradient-bar
      it "renders the fill clip window" do
        expect(node.css(".pito-context-meter__fill")).not_to be_empty
      end

      it "renders the inner gradient-bar inside the fill" do
        expect(node.css(".pito-context-meter__fill .pito-context-meter__gradient-bar")).not_to be_empty
      end

      it "sets width on the fill (N% of track)" do
        fill = node.css(".pito-context-meter__fill").first
        expect(fill["style"]).to include("width: 50.0%")
      end

      it "sets --ctx-pct CSS custom property on the fill for the gradient calc" do
        fill = node.css(".pito-context-meter__fill").first
        expect(fill["style"]).to include("--ctx-pct: 50.0")
      end
    end

    context "when at 0 events" do
      # CTXF3: no fill rendered at 0% (avoids division-by-zero in calc)
      it "does not render the fill or gradient-bar at 0%" do
        expect(node.css(".pito-context-meter__fill")).to be_empty
        expect(node.css(".pito-context-meter__gradient-bar")).to be_empty
      end
    end

    context "when pegged at 100" do
      let(:event_count) { 150 }

      it "shows 100% counter" do
        expect(node.text).to include("100%")
      end

      it "renders the gradient-bar at 100%" do
        expect(node.css(".pito-context-meter__gradient-bar")).not_to be_empty
      end
    end
  end

  # CTXF5: auth-gating is enforced in the view (conversations/show.html.erb),
  # not the component itself. The component is renderable by any caller;
  # the view wraps it in `if @authenticated`. Verify the component renders
  # normally (it has no auth awareness of its own).
  describe "CTXF5 — component is auth-agnostic (gate lives in the view)" do
    it "renders at 0 events without raising" do
      expect { render_inline(described_class.new(event_count: 0)) }.not_to raise_error
    end

    it "renders at 50 events without raising" do
      expect { render_inline(described_class.new(event_count: 50)) }.not_to raise_error
    end
  end

  # ── G44 regression guard — the live-rename slot ─────────────────────────────
  #
  # broadcast_conversation_name replaces `#pito-chatbox-conversation-name` on
  # the conversation stream. The meter header MUST always carry that slot —
  # when it once rendered a bare span instead, /rename became a silent no-op
  # in the live DOM and the new name only appeared after a reload.

  describe "the conversation-name slot (G44)" do
    slot = "#" + Pito::Shell::Chatbox::NameComponent::SLOT_ID

    it "is present when the conversation is named, with the name inside" do
      node = render_inline(described_class.new(event_count: 5, conversation_name: "android"))
      expect(node.at_css(slot)).to be_present
      expect(node.at_css(slot).text.strip).to eq("android")
    end

    it "is present even when Unnamed — a live rename needs a target to replace" do
      node = render_inline(described_class.new(event_count: 5))
      expect(node.at_css(slot)).to be_present
      expect(node.at_css(slot).text.strip).to be_empty
    end
  end
end
