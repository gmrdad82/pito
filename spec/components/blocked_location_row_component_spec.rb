require "rails_helper"

RSpec.describe BlockedLocationRowComponent, type: :component do
  context "active row" do
    let(:row) do
      create(:blocked_location,
             source_surface: :web,
             fingerprint_hash: ("a" * 64),
             ip_prefix: "1.1.1.0/24",
             attempt_count: 3)
    end

    it "renders the source badge in uppercase" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("WEB")
    end

    it "renders the short fingerprint (first 12 hex)" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("a" * 12)
    end

    it "renders the ip prefix" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("1.1.1.0/24")
    end

    it "renders the attempt count" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("3")
    end

    it "renders the active state label in bold" do
      render_inline(described_class.new(row: row))
      expect(page).to have_css("strong", text: "active")
    end

    it "renders the [unblock] bracketed link to the action-screen" do
      render_inline(described_class.new(row: row))
      expect(page).to have_link(
        href: "/settings/security/blocks/#{row.id}/unblocking"
      )
      expect(page).to have_css("a", text: /unblock/)
    end

    it "renders the [view] link to the detail page" do
      render_inline(described_class.new(row: row))
      expect(page).to have_link(href: "/settings/security/blocks/#{row.id}")
    end

    it "hides the unblock link when show_unblock_link: false" do
      render_inline(described_class.new(row: row, show_unblock_link: false))
      expect(page).not_to have_link(
        href: "/settings/security/blocks/#{row.id}/unblocking"
      )
    end

    it "renders the last-attempt timestamp when present" do
      row.update!(last_attempt_at: Time.utc(2026, 5, 10, 12, 34))
      render_inline(described_class.new(row: row))
      expect(page).to have_text("2026-05-10 12:34")
    end

    it "falls back to '—' when no last-attempt timestamp" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("—")
    end
  end

  context "soft-unblocked row" do
    let(:row) { create(:blocked_location, :unblocked) }

    it "renders the muted 'unblocked' label" do
      render_inline(described_class.new(row: row))
      expect(page).to have_css("span.text-muted", text: "unblocked")
    end

    it "does NOT render the [unblock] action-screen link" do
      render_inline(described_class.new(row: row))
      expect(page).not_to have_link(
        href: "/settings/security/blocks/#{row.id}/unblocking"
      )
    end

    it "still renders the [view] detail link" do
      render_inline(described_class.new(row: row))
      expect(page).to have_link(href: "/settings/security/blocks/#{row.id}")
    end
  end

  context "tui-source row" do
    let(:row) { create(:blocked_location, source_surface: :tui) }

    it "renders the TUI source badge" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("TUI")
    end
  end

  context "mcp-source row" do
    let(:row) { create(:blocked_location, source_surface: :mcp) }

    it "renders the MCP source badge" do
      render_inline(described_class.new(row: row))
      expect(page).to have_text("MCP")
    end
  end
end
