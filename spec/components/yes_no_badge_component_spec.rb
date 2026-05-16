require "rails_helper"

# 2026-05-16 (sessions revamp v2). Yes / no status badge.
#
# Thin wrapper around `StatusBadgeComponent` that renders a boolean as
# `yes` (green via `:yes`) or `no` (muted via `:no`).
RSpec.describe YesNoBadgeComponent, type: :component do
  describe "boolean value" do
    it "renders `yes` with the `--yes` modifier when value is true" do
      render_inline(described_class.new(value: true))
      expect(page).to have_css("span.status-badge.status-badge--yes", text: "yes")
    end

    it "renders `no` with the `--no` modifier when value is false" do
      render_inline(described_class.new(value: false))
      expect(page).to have_css("span.status-badge.status-badge--no", text: "no")
    end

    it "renders `no` with the `--no` modifier when value is nil" do
      render_inline(described_class.new(value: nil))
      expect(page).to have_css("span.status-badge.status-badge--no", text: "no")
    end
  end

  describe "yes/no string boundary coercion" do
    # CLAUDE.md hard rule — external booleans use yes/no strings.
    # The component accepts both shapes so a render fed by a JSON
    # blob or MCP response does not need per-call coercion.
    it "treats the literal string `yes` as truthy" do
      render_inline(described_class.new(value: "yes"))
      expect(page).to have_css("span.status-badge.status-badge--yes")
    end

    it "treats the literal string `true` as truthy" do
      render_inline(described_class.new(value: "true"))
      expect(page).to have_css("span.status-badge.status-badge--yes")
    end

    it "treats the integer 1 as truthy" do
      render_inline(described_class.new(value: 1))
      expect(page).to have_css("span.status-badge.status-badge--yes")
    end

    it "treats the string `1` as truthy" do
      render_inline(described_class.new(value: "1"))
      expect(page).to have_css("span.status-badge.status-badge--yes")
    end

    it "treats `no` as falsy" do
      render_inline(described_class.new(value: "no"))
      expect(page).to have_css("span.status-badge.status-badge--no")
    end

    it "treats an unknown string as falsy" do
      render_inline(described_class.new(value: "maybe"))
      expect(page).to have_css("span.status-badge.status-badge--no")
    end
  end

  describe "structural chrome" do
    it "renders exactly one span (delegates to StatusBadgeComponent)" do
      render_inline(described_class.new(value: true))
      expect(page).to have_css("span.status-badge", count: 1)
    end

    it "renders the label as plain text — no bracket characters" do
      render_inline(described_class.new(value: true))
      badge = page.find("span.status-badge")
      expect(badge.text).not_to include("[")
      expect(badge.text).not_to include("]")
    end
  end
end
