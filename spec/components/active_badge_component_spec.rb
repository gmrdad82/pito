require "rails_helper"

# 2026-05-16 (sessions revamp v2). Active status badge.
#
# Thin wrapper around `StatusBadgeComponent` rendering a fixed `active`
# label with green (`:success`) styling. Optional `label:` override
# keeps the green semantics while letting the call site swap wording.
RSpec.describe ActiveBadgeComponent, type: :component do
  describe "default rendering" do
    it "renders the literal `active` label" do
      render_inline(described_class.new)
      expect(page).to have_css("span.status-badge", text: "active")
    end

    it "uses the `--success` (green) modifier" do
      render_inline(described_class.new)
      expect(page).to have_css("span.status-badge.status-badge--success")
    end

    it "renders exactly one span (delegates to StatusBadgeComponent)" do
      render_inline(described_class.new)
      expect(page).to have_css("span.status-badge", count: 1)
    end

    it "renders the label as plain text — no bracket characters" do
      render_inline(described_class.new)
      badge = page.find("span.status-badge")
      expect(badge.text).not_to include("[")
      expect(badge.text).not_to include("]")
    end
  end

  describe "label override" do
    it "accepts a `label:` override and keeps the green styling" do
      render_inline(described_class.new(label: "live"))
      expect(page).to have_css("span.status-badge.status-badge--success", text: "live")
    end

    it "accepts `on` as a label and keeps the green styling" do
      render_inline(described_class.new(label: "on"))
      expect(page).to have_css("span.status-badge.status-badge--success", text: "on")
    end
  end
end
