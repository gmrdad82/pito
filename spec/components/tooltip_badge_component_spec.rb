require "rails_helper"

# 2026-05-16 (sessions revamp v2). Generic tooltip badge primitive.
#
# Renders a bordered `.status-badge` whose short visible `label:`
# reveals a longer `tooltip:` string on hover (or keyboard focus). The
# tooltip is a CSS-only `::after` pseudo keyed off `data-tooltip` —
# same pattern as `viewer-time-heatmap__cell`. A sibling
# `<span role="tooltip">.sr-only` carries the same text for assistive
# tech via `aria-describedby`.
RSpec.describe TooltipBadgeComponent, type: :component do
  describe "default rendering (neutral variant)" do
    before do
      render_inline(described_class.new(label: "ip", tooltip: "203.0.113.42"))
    end

    it "renders a `.status-badge` host span carrying the label" do
      expect(page).to have_css("span.status-badge", text: /ip/)
    end

    it "applies the neutral status-badge modifier by default" do
      expect(page).to have_css("span.status-badge--neutral")
    end

    it "carries the `tooltip-host` class for the CSS-only hover/focus reveal" do
      expect(page).to have_css("span.tooltip-host")
    end

    it "exposes the tooltip content via `data-tooltip` (the `::after` content source)" do
      host = page.find("span.tooltip-host")
      expect(host["data-tooltip"]).to eq("203.0.113.42")
    end

    it "is focusable via the keyboard (`tabindex=0`)" do
      host = page.find("span.tooltip-host")
      expect(host["tabindex"]).to eq("0")
    end

    it "wires `aria-describedby` to a sibling `role=tooltip` element" do
      host = page.find("span.tooltip-host")
      described_id = host["aria-describedby"]
      expect(described_id).to be_present
      expect(page).to have_css("##{described_id}[role='tooltip']", text: "203.0.113.42", visible: :all)
    end

    it "places the tooltip text inside a `.sr-only` sibling so screen readers can announce it" do
      expect(page).to have_css("span.tooltip-host span.sr-only[role='tooltip']", text: "203.0.113.42", visible: :all)
    end

    it "renders the label as plain text — no bracket characters (the border IS the visual delimiter)" do
      host = page.find("span.tooltip-host")
      visible = host.text(:all).sub("203.0.113.42", "").strip
      expect(visible).not_to include("[")
      expect(visible).not_to include("]")
    end
  end

  describe "tooltip-id uniqueness" do
    it "generates a distinct DOM id per instance so multiple badges on one page do not collide" do
      render_inline(described_class.new(label: "ip", tooltip: "10.0.0.1"))
      first_id = page.find("span.tooltip-host")["aria-describedby"]

      render_inline(described_class.new(label: "ip", tooltip: "10.0.0.2"))
      second_id = page.find("span.tooltip-host")["aria-describedby"]

      expect(first_id).to be_present
      expect(second_id).to be_present
      expect(first_id).not_to eq(second_id)
    end
  end

  describe "variant override" do
    it "accepts a `variant:` matching `StatusBadgeComponent::KINDS` and emits the `--<variant>` modifier" do
      render_inline(described_class.new(label: "warn", tooltip: "stale", variant: :warn))
      expect(page).to have_css("span.status-badge.status-badge--warn.tooltip-host")
    end

    it "accepts the `:success` variant" do
      render_inline(described_class.new(label: "ok", tooltip: "ok", variant: :success))
      expect(page).to have_css("span.status-badge--success.tooltip-host")
    end

    it "accepts the `:urgent` variant (the danger-red shade)" do
      render_inline(described_class.new(label: "fail", tooltip: "boom", variant: :urgent))
      expect(page).to have_css("span.status-badge--urgent.tooltip-host")
    end

    it "falls back to `:neutral` when given an unknown variant (no defensive guard at the call site)" do
      render_inline(described_class.new(label: "x", tooltip: "y", variant: :mystery))
      expect(page).to have_css("span.status-badge--neutral.tooltip-host")
    end

    it "falls back to `:neutral` when given `nil`" do
      render_inline(described_class.new(label: "x", tooltip: "y", variant: nil))
      expect(page).to have_css("span.status-badge--neutral.tooltip-host")
    end

    it "accepts the variant as a string and coerces to a symbol" do
      render_inline(described_class.new(label: "ok", tooltip: "ok", variant: "success"))
      expect(page).to have_css("span.status-badge--success.tooltip-host")
    end
  end

  describe "tooltip text coercion" do
    it "renders the tooltip text verbatim for a normal string" do
      render_inline(described_class.new(label: "ip", tooltip: "203.0.113.7"))
      host = page.find("span.tooltip-host")
      expect(host["data-tooltip"]).to eq("203.0.113.7")
    end

    it "falls back to an em-dash when tooltip is nil" do
      render_inline(described_class.new(label: "ip", tooltip: nil))
      host = page.find("span.tooltip-host")
      expect(host["data-tooltip"]).to eq("—")
    end

    it "falls back to an em-dash when tooltip is an empty string" do
      render_inline(described_class.new(label: "ip", tooltip: ""))
      host = page.find("span.tooltip-host")
      expect(host["data-tooltip"]).to eq("—")
    end

    it "coerces non-string tooltips via `to_s` (numeric, etc.)" do
      render_inline(described_class.new(label: "n", tooltip: 42))
      host = page.find("span.tooltip-host")
      expect(host["data-tooltip"]).to eq("42")
    end

    it "keeps the sibling `role=tooltip` text in sync with the `data-tooltip` attribute" do
      render_inline(described_class.new(label: "ip", tooltip: nil))
      host = page.find("span.tooltip-host")
      sibling = page.find("##{host['aria-describedby']}", visible: :all)
      expect(host["data-tooltip"]).to eq(sibling.text(:all))
    end
  end

  describe "structural chrome" do
    it "renders exactly one tooltip-host span" do
      render_inline(described_class.new(label: "ip", tooltip: "10.0.0.1"))
      expect(page).to have_css("span.tooltip-host", count: 1)
    end
  end
end
