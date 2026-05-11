require "rails_helper"

# 2026-05-11 polish (Fix 1) — bulk-operation item row partial.
#
# The action-gutter cell on each row of the sync-progress table.
# When a per-item status flips to `succeeded`, the partial used to
# render a bare `<span class="dot-done">done</span>` literal; per the
# 2026-05-11 polish wave it now renders the shared
# `StatusBadgeComponent` with `kind: :success` so the bordered-badge
# ceremony matches the rest of the app (notifications severity,
# calendar all-day, etc.). The other statuses (`failed`, `skipped`,
# pending dot-loader) are unchanged.
RSpec.describe "bulk_operations/_item_row.html.erb", type: :view do
  def render_row(status, item_id: 1)
    render partial: "bulk_operations/item_row",
           locals: { item_id: item_id, status: status }
  end

  describe "succeeded status — Fix 1 StatusBadge migration" do
    it "renders the `done` label inside a `.status-badge--success` span" do
      render_row("succeeded")
      doc = Nokogiri::HTML.fragment(rendered)
      badge = doc.css("span.status-badge.status-badge--success").first
      expect(badge).not_to be_nil
      expect(badge.text.strip).to eq("done")
    end

    it "no longer renders the legacy `<span class=\"dot-done\">done</span>` literal" do
      render_row("succeeded")
      expect(rendered).not_to match(%r{<span class="dot-done">})
    end

    it "stamps the action-gutter `<td>` with the per-item status id" do
      render_row("succeeded", item_id: 42)
      expect(rendered).to include('id="item_status_42"')
    end
  end

  describe "non-success statuses — unchanged" do
    it "renders the fail marker for `failed`" do
      render_row("failed")
      expect(rendered).to include('class="dot-fail"')
      expect(rendered).to include("fail")
    end

    it "renders the skip badge for `skipped`" do
      render_row("skipped")
      expect(rendered).to include("skip-badge")
      expect(rendered).to include("[skip]")
    end

    it "renders the dot-loader for pending statuses" do
      render_row("pending")
      expect(rendered).to include('class="dot-loader"')
    end
  end
end
