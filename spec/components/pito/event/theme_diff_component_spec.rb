# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ThemeDiffComponent do
  let(:conversation) { Conversation.create! }
  let(:turn) { create(:turn, conversation:) }

  let(:base_event) do
    create(:event, conversation:, turn:, kind: "theme_diff", position: 1, payload: {})
  end

  let(:preview_payload) do
    {
      "phase"          => "preview",
      "granularity"    => "char",
      "previewed_slug" => "dracula",
      "from_text"      => "Old list text",
      "reply_handle"   => "beta-1234",
      "reply_target"   => "theme_diff",
      "sections"       => [
        {
          "title" => "Dark",
          "rows"  => [
            { "key" => "  dracula",     "value" => "Dracula" },
            { "key" => "  tokyo-night", "value" => "Tokyo Night" }
          ]
        },
        {
          "title" => "Light",
          "rows"  => [
            { "key" => "  github-light", "value" => "GitHub Light" }
          ]
        }
      ]
    }
  end

  let(:apply_payload) do
    {
      "phase"          => "apply",
      "granularity"    => "line",
      "body"           => "Your eyes are now glazed by Dracula.",
      "from_text"      => "Pick a theme\nDark\n  dracula Dracula\n  tokyo-night Tokyo Night\nLight\n  github-light GitHub Light",
      "reply_handle"   => "beta-1234",
      "reply_target"   => "theme_diff",
      "reply_consumed" => true
    }
  end

  # ── Segment root & id ────────────────────────────────────────────────────────

  describe "root Segment id" do
    it "renders id='event_<id>' when event is present" do
      node = render_inline(described_class.new(payload: preview_payload, event: base_event))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to eq("event_#{base_event.id}")
    end

    it "renders no id when event is nil" do
      node = render_inline(described_class.new(payload: preview_payload, event: nil))
      segment = node.css(".pito-segment").first
      expect(segment["id"]).to be_nil
    end
  end

  # ── diff-reveal controller wiring ────────────────────────────────────────────

  describe "instant render (item 18: no diff-reveal morph)" do
    subject(:node) { render_inline(described_class.new(payload: preview_payload, event: base_event)) }

    it "has no diff-reveal controller or cell wiring" do
      expect(node.css("[data-controller~='pito--diff-reveal']")).to be_empty
      expect(node.css("[data-pito--diff-reveal-target]")).to be_empty
    end
  end

  # ── Preview phase ────────────────────────────────────────────────────────────

  describe "preview phase rendering" do
    subject(:node) { render_inline(described_class.new(payload: preview_payload, event: base_event)) }

    it "renders section headers for Dark and Light" do
      text = node.text
      expect(text).to include("Dark").and include("Light")
    end

    it "renders all theme slugs as text content" do
      text = node.text
      expect(text).to include("dracula")
      expect(text).to include("tokyo-night")
      expect(text).to include("github-light")
    end

    it "renders the previewed row with border + surface background classes" do
      # Find the div wrapping the previewed dracula row
      bordered = node.css("div.border.border-line-default.bg-surface.rounded").first
      expect(bordered).not_to be_nil
    end

    it "shows the '‹preview›' marker as plain text (no diff cell)" do
      expect(node.css("span[data-pito--diff-reveal-target='cell']")).to be_empty
      expect(node.text).to include("‹preview›")
    end
  end

  # ── Apply phase ──────────────────────────────────────────────────────────────

  describe "apply phase rendering" do
    subject(:node) { render_inline(described_class.new(payload: apply_payload, event: base_event)) }

    it "renders the quip as plain text instantly (no diff cell)" do
      expect(node.css("span[data-pito--diff-reveal-target='cell']")).to be_empty
      expect(node.text).to include("Your eyes are now glazed by Dracula.")
    end

    it "does NOT render section rows (apply phase is a single confirmation)" do
      expect(node.text).not_to include("GitHub Light")
    end
  end

  # ── follow-up handle in the single meta line (no usage/affordance line) ─────────

  describe "follow-up handle in the single meta line" do
    it "shows the #handle when payload-only (no persisted event to gate against)" do
      node = render_inline(described_class.new(payload: preview_payload, event: nil))
      expect(node.css(".pito-echo__meta").text).to include("beta-1234")
    end

    # theme_diff is a legacy render path: the theme picker moved fully
    # client-side and no current code path mints a theme_diff event, so any
    # persisted row is an OLD one. "theme_diff" is neither a Registry-registered
    # reply_target (no handler claims it) nor a kind the universal
    # share/revoke/unshare `kinds:` list covers — zero available actions. The
    # owner's "no actions → no handle, no chip" rule (Pito::FollowUp.
    # renderable_actions?) retires its long-stale, already-unroutable handle.
    it "hides the #handle for a persisted event — theme_diff has zero available actions" do
      node = render_inline(described_class.new(payload: preview_payload, event: base_event))
      expect(node.css(".pito-echo__meta").text).not_to include("beta-1234")
    end

    it "NEVER renders a separate usage/affordance line" do
      node = render_inline(described_class.new(payload: preview_payload, event: base_event))
      expect(node.css("div.mt-1.text-fg-faded")).to be_empty
    end

    it "drops the #handle in apply phase (reply_consumed: true)" do
      node = render_inline(described_class.new(payload: apply_payload, event: base_event))
      expect(node.css(".pito-echo__meta").text).not_to include("beta-1234")
    end

    it "shows no handle when reply_handle is absent" do
      payload = preview_payload.except("reply_handle", "reply_target")
      node = render_inline(described_class.new(payload:, event: base_event))
      expect(node.css(".pito-echo__meta").text).not_to include("beta-1234")
    end
  end
end
