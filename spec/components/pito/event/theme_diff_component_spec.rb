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
      theme_diff:     true,
      theme_list:     true,
      phase:          "preview",
      granularity:    "char",
      previewed_slug: "dracula",
      from_text:      "Old list text",
      sections: [
        {
          title: "Dark",
          rows: [
            { key: "  dracula",    value: "Dracula" },
            { key: "  tokyo-night", value: "Tokyo Night" }
          ]
        },
        {
          title: "Light",
          rows: [
            { key: "  github-light", value: "GitHub Light" }
          ]
        }
      ]
    }
  end

  let(:apply_payload) do
    {
      theme_diff:  true,
      phase:       "apply",
      granularity: "line",
      body:        "Your eyes are now glazed by Dracula.",
      from_text:   "Pick a theme\nDark\n  dracula Dracula\n  tokyo-night Tokyo Night\nLight\n  github-light GitHub Light"
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

  # ── Quips sampler determinism (T12.4) ────────────────────────────────────────

  describe "Pito::Themes::Quips.applied" do
    it "returns a non-empty string containing the label" do
      quip = Pito::Themes::Quips.applied("Dracula")
      expect(quip).to be_a(String).and be_present
      expect(quip).to include("Dracula")
    end

    it "is deterministic with a seeded rng" do
      rng = Random.new(42)
      q1  = Pito::Themes::Quips.applied("Nord", rng: Random.new(42))
      q2  = Pito::Themes::Quips.applied("Nord", rng: rng.clone)
      expect(q1).to eq(q2)
    end

    it "varies with different seeds" do
      entries = I18n.t("pito.hashtag.theme.apply.quips")
      # With 25 entries two seeds close together are likely to differ
      results = (0..24).map { |seed| Pito::Themes::Quips.applied("Dracula", rng: Random.new(seed)) }
      expect(results.uniq.size).to be > 1
    end
  end
end
