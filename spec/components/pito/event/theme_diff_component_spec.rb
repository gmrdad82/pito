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

  describe "pito--diff-reveal controller wiring" do
    subject(:node) { render_inline(described_class.new(payload: preview_payload, event: base_event)) }

    it "wraps content in a div with data-controller='pito--diff-reveal'" do
      wrapper = node.css("[data-controller='pito--diff-reveal']").first
      expect(wrapper).not_to be_nil
    end

    it "sets data-pito--diff-reveal-granularity-value" do
      wrapper = node.css("[data-controller='pito--diff-reveal']").first
      expect(wrapper["data-pito--diff-reveal-granularity-value"]).to eq("char")
    end

    it "sets data-pito--diff-reveal-phase-value" do
      wrapper = node.css("[data-controller='pito--diff-reveal']").first
      expect(wrapper["data-pito--diff-reveal-phase-value"]).to eq("preview")
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

    it "renders a diff cell span for the previewed row's marker" do
      cells = node.css("span[data-pito--diff-reveal-target='cell']")
      expect(cells).not_to be_empty
    end

    it "diff cell textContent includes the '‹preview›' marker" do
      cell = node.css("span[data-pito--diff-reveal-target='cell']").first
      expect(cell.text).to include("‹preview›")
    end

    it "diff cell data-from is the row's original text (without preview marker)" do
      cell = node.css("span[data-pito--diff-reveal-target='cell']").first
      expect(cell["data-from"]).to eq("  dracula")
    end

    it "non-previewed rows do NOT have diff cell markup" do
      # Count all diff cells — should only be 1 (the previewed row)
      cells = node.css("span[data-pito--diff-reveal-target='cell']")
      expect(cells.size).to eq(1)
    end
  end

  # ── Apply phase ──────────────────────────────────────────────────────────────

  describe "apply phase rendering" do
    subject(:node) { render_inline(described_class.new(payload: apply_payload, event: base_event)) }

    it "sets phase value to 'apply' on the controller wrapper" do
      wrapper = node.css("[data-controller='pito--diff-reveal']").first
      expect(wrapper["data-pito--diff-reveal-phase-value"]).to eq("apply")
    end

    it "sets granularity to 'line'" do
      wrapper = node.css("[data-controller='pito--diff-reveal']").first
      expect(wrapper["data-pito--diff-reveal-granularity-value"]).to eq("line")
    end

    it "renders ONE diff cell with the quip as textContent (final state)" do
      cells = node.css("span[data-pito--diff-reveal-target='cell']")
      expect(cells.size).to eq(1)
      expect(cells.first.text).to eq("Your eyes are now glazed by Dracula.")
    end

    it "diff cell data-from is the old list's plain text" do
      cell = node.css("span[data-pito--diff-reveal-target='cell']").first
      expect(cell["data-from"]).to include("Pick a theme")
    end

    it "does NOT render section rows (apply phase is a single confirmation)" do
      expect(node.text).not_to include("GitHub Light")
    end
  end

  # ── follow-up handle in the single meta line (no usage/affordance line) ─────────

  describe "follow-up handle in the single meta line" do
    it "shows the #handle in preview phase (reply_handle present, not consumed)" do
      node = render_inline(described_class.new(payload: preview_payload, event: base_event))
      expect(node.css(".pito-echo__meta").text).to include("beta-1234")
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

  # ── Quips via copy engine ────────────────────────────────────────────────────

  describe "Pito::Themes::Quips.applied (delegates to Pito::Copy)" do
    it "returns a non-empty string containing the label" do
      quip = Pito::Themes::Quips.applied("Dracula")
      expect(quip).to be_a(String).and be_present
      expect(quip).to include("Dracula")
    end

    it "interpolates the theme label into the quip" do
      quip = Pito::Themes::Quips.applied("Tokyo Night")
      expect(quip).to include("Tokyo Night")
    end

    it "returns a variant from the pito.copy.theme.applied pool" do
      entries = I18n.t("pito.copy.theme.applied")
      quip    = Pito::Themes::Quips.applied("Dracula")
      # Strip out the %{theme} interpolation to compare pool membership
      candidates = entries.map { |e| e % { theme: "Dracula" } }
      expect(candidates).to include(quip)
    end
  end
end
