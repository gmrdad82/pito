require "rails_helper"

# Phase 16 §3 UX restructure 2026-05-10 — badge renders as a `<sup>`
# (no surrounding brackets) when unread_count > 0; empty wrapper when 0.
RSpec.describe "notifications/_badge.html.erb", type: :view do
  let(:sup_pattern) { /<sup[^>]*notifications-badge-count[^>]*>\s*(\d+)\s*<\/sup>/ }

  it "renders an empty wrapper when unread_count is 0" do
    render partial: "notifications/badge", locals: { unread_count: 0 }
    expect(rendered).to include('id="notifications_badge"')
    expect(rendered).not_to match(sup_pattern)
  end

  it "renders <sup>N</sup> when unread_count > 0" do
    render partial: "notifications/badge", locals: { unread_count: 3 }
    expect(rendered).to match(sup_pattern)
    expect(rendered[sup_pattern, 1]).to eq("3")
  end

  it "carries the stable dom_id `notifications_badge`" do
    render partial: "notifications/badge", locals: { unread_count: 5 }
    expect(rendered).to include('id="notifications_badge"')
  end

  it "renders an aria-label for assistive tech" do
    render partial: "notifications/badge", locals: { unread_count: 5 }
    expect(rendered).to include('aria-label="5 unread notifications"')
  end

  it "treats nil count defensively (falsy -> no <sup>)" do
    render partial: "notifications/badge", locals: { unread_count: nil }
    expect(rendered).not_to match(sup_pattern)
  end

  it "does NOT wrap the count in brackets" do
    render partial: "notifications/badge", locals: { unread_count: 3 }
    # Old shape: `[ 3 ]`. New shape strips the brackets entirely.
    expect(rendered).not_to match(/\[\s*3\s*\]/)
  end
end
