require "rails_helper"

# Phase 16 §3 — System spec for the /notifications index.
# Uses rack_test (HTTP-only, no JS) — Turbo Stream live updates and
# Stimulus-driven dynamic-button text are covered by request and unit
# specs. The index spec asserts the SSR shape: rows render, the filter
# checkbox toggles correctly, mark-all-read button POSTs, and the
# cleanup caption is present.
#
# UX restructure 2026-05-10:
#   - `[ all ]` / `[ unread ]` bracketed-link toggles replaced by a
#     `[ ] unread` checkbox chip.
#   - Per-row `[ mark read ]` action removed; bulk action covers it.
#   - Notification rows open a modal (JS) — the link's href still
#     points at the canonical /notifications/:id show URL so :rack_test
#     follows it for fallback assertions.
RSpec.describe "Notifications index", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { driven_by(:rack_test) }

  it "shows the empty state when there are no rows" do
    visit "/notifications"
    expect(page).to have_content("no notifications yet.")
  end

  it "shows the index heading" do
    visit "/notifications"
    expect(page).to have_selector("h1", text: "notifications")
  end

  it "renders the cleanup caption under the heading" do
    visit "/notifications"
    expect(page).to have_content("notifications are deleted 7 days after being read.")
  end

  it "renders rows when notifications exist" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).to include(ActionView::RecordIdentifier.dom_id(notif))
  end

  it "puts unread rows above read rows" do
    read_row = travel_to(2.hours.ago) { create(:notification, :read, :calendar_entry_firing) }
    unread_row = travel_to(1.hour.ago) { create(:notification, :video_published) }
    visit "/notifications"
    body = page.body
    unread_pos = body.index(ActionView::RecordIdentifier.dom_id(unread_row))
    read_pos   = body.index(ActionView::RecordIdentifier.dom_id(read_row))
    expect(unread_pos).to be < read_pos
  end

  it "renders the [ ] unread filter chip" do
    visit "/notifications"
    # FilterChipComponent emits `<a class="filter-chip">[ ] unread</a>`.
    expect(page).to have_selector("a.filter-chip", text: /unread/i)
    expect(page).to have_content("[ ]")
  end

  it "click [ ] unread chip flips the URL to ?filter=unread" do
    create(:notification, :video_published)
    visit "/notifications"
    find("a.filter-chip", text: /unread/i).click
    expect(page.current_url).to include("filter=unread")
  end

  it "filter chip renders [x] when filter=unread is active" do
    create(:notification, :video_published)
    visit "/notifications?filter=unread"
    expect(page).to have_selector("a.filter-chip .md-check-static", text: "[x]")
  end

  it "?filter=unread shows only unread rows" do
    unread_row = create(:notification, :video_published)
    read_row   = create(:notification, :read, :calendar_entry_firing)
    visit "/notifications?filter=unread"
    expect(page.body).to include(ActionView::RecordIdentifier.dom_id(unread_row))
    expect(page.body).not_to include(ActionView::RecordIdentifier.dom_id(read_row))
  end

  it "renders [ mark all as read ] button when there are unread rows" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_button("[mark all as read]")
  end

  it "click [ mark all as read ] flips every unread to read" do
    create(:notification, :video_published)
    create(:notification, :sync_error)
    visit "/notifications"
    click_button("[mark all as read]")
    expect(Notification.unread.count).to eq(0)
  end

  it "renders a row checkbox for each unread notification" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_selector('input[type="checkbox"][data-bulk-select-target="checkbox"]')
  end

  # 2026-05-10 — checkbox-always-visible refinement. The negative
  # guard previously here asserted that READ rows skip the checkbox
  # column. That layout was replaced by the always-on bulk-select
  # pattern used app-wide (channels / videos / projects notes), so
  # read rows now carry a checkbox too. The dynamic `[ mark N as
  # read ]` controller filters by `.notification-unread` when
  # counting, so the always-on column has no functional cost.
  it "ALSO renders a row checkbox for read notifications (always-on column)" do
    create(:notification, :read, :video_published)
    visit "/notifications?filter=all"
    expect(page).to have_selector('input[type="checkbox"][data-bulk-select-target="checkbox"]')
  end

  it "shows the webhook misconfigured banner when an unread row has last_error" do
    create(:notification, :video_published, last_error: "boom")
    visit "/notifications"
    expect(page).to have_content("webhook delivery failing")
  end

  it "hides the banner when no unread rows have last_error" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).not_to have_content("webhook delivery failing")
  end

  it "row link points at /notifications/:id (modal-trigger fallback)" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    # The link carries `data-action="click->notification-modal#open"`
    # so JS opens the modal; the href stays as the show path so a
    # rack_test (no-JS) click follows it.
    row_link = find("a.notification-title")
    expect(row_link[:href]).to eq(notification_path(notif))
    expect(row_link["data-action"]).to include("notification-modal#open")
  end

  it "renders the notification detail dialog at the bottom of the page" do
    create(:notification, :video_published)
    visit "/notifications"
    # The modal mount is a single <dialog> with the
    # notification_detail_frame Turbo Frame inside it.
    expect(page).to have_selector('dialog[data-notification-modal-target="dialog"]', visible: :all)
    expect(page).to have_selector('turbo-frame#notification_detail_frame', visible: :all)
  end

  it "does NOT include `data-turbo-confirm` anywhere" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).not_to include("data-turbo-confirm")
  end
end
