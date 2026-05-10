require "rails_helper"

# Phase 16 §3 — Badge live-update behavior.
#
# Capybara :rack_test cannot actually subscribe to a Turbo Stream
# (no JS). The test asserts the SSR shape of the badge fragment AND
# the broadcast wiring on the model. End-to-end live update is
# manually verified per the playbook.
#
# UX restructure 2026-05-10 — the badge is rendered as
# `<sup class="notifications-badge-count">N</sup>` next to the
# `[notifications]` nav link, NOT a bracketed `[ N ]` span.
RSpec.describe "Notifications badge live update", type: :system do
  before { driven_by(:rack_test) }

  let(:sup_pattern) { /<sup[^>]*notifications-badge-count[^>]*>\s*(\d+)\s*<\/sup>/ }

  it "renders the badge with <sup>N</sup> when unread_count > 0" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).to match(sup_pattern)
    expect(page.body[sup_pattern, 1]).to eq("1")
  end

  it "renders an empty wrapper when unread_count == 0" do
    create(:notification, :read, :video_published)
    visit "/notifications"
    # Wrapper exists (so Turbo can target it), but no <sup> inside.
    expect(page.body).to include('id="notifications_badge"')
    badge_html = page.body[/<span id="notifications_badge"[^>]*>(.*?)<\/span>/m, 1].to_s
    expect(badge_html).not_to match(sup_pattern)
  end

  it "broadcasts the badge replace on Notification create" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with(
        "notifications_badge",
        target: "notifications_badge",
        partial: "notifications/badge",
        locals: { unread_count: 1 }
      )
    expect(Turbo::StreamsChannel).to receive(:broadcast_prepend_later_to).at_least(:once)
    create(:notification, :video_published)
  end

  it "broadcasts the badge replace on read-state flip" do
    notification = create(:notification, :video_published)
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with(
        "notifications_badge",
        target: "notifications_badge",
        partial: "notifications/badge",
        locals: { unread_count: 0 }
      )
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with(
        "notifications_index",
        hash_including(target: ActionView::RecordIdentifier.dom_id(notification))
      )
    notification.mark_read!
  end

  it "decrements live when the last unread is read (badge wrapper still present)" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).to match(sup_pattern)
    notif.mark_read!
    visit "/notifications"
    badge_html = page.body[/<span id="notifications_badge"[^>]*>(.*?)<\/span>/m, 1].to_s
    expect(badge_html).not_to match(sup_pattern)
  end
end
