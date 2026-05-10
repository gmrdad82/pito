require "rails_helper"

# Phase 16 §3 — System spec for the /notifications index.
# Uses rack_test (HTTP-only, no JS) — Turbo Stream live updates are
# covered by the request spec. The index spec asserts the SSR shape:
# rows render, filters work, mark-read button POSTs and the row
# flips read.
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

  it "click [ all ] navigates to ?filter=all (all is default)" do
    create(:notification, :video_published)
    visit "/notifications?filter=unread"
    # The filter cluster is the second `.dot-list` on the page (the
    # first is the inner wrapper for the notifications subroutes).
    # Use within `[id^="notifications_list"]`'s container — the
    # filter is in a sibling .dot-list. Match the filter `all` link
    # by href.
    click_link href: "/notifications"
    expect(page.current_url).to match(/notifications\b/)
    expect(page.current_url).not_to include("filter=unread")
  end

  it "click [ unread ] filters to unread only" do
    unread_row = create(:notification, :video_published)
    read_row   = create(:notification, :read, :calendar_entry_firing)
    visit "/notifications"
    click_link href: "/notifications?filter=unread"
    expect(page.current_url).to include("filter=unread")
    expect(page.body).to include(ActionView::RecordIdentifier.dom_id(unread_row))
    expect(page.body).not_to include(ActionView::RecordIdentifier.dom_id(read_row))
  end

  it "renders [ mark all read ] button when there are unread rows" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_button("[mark all read]").or have_link("mark all read")
  end

  it "click [ mark all read ] flips every unread to read" do
    create(:notification, :video_published)
    create(:notification, :sync_error)
    visit "/notifications"
    click_button("[mark all read]")
    expect(Notification.unread.count).to eq(0)
  end

  it "renders the per-row [ mark read ] action" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_button("[mark read]")
  end

  it "click per-row [ mark read ] flips that row to read" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    first(:button, "[mark read]").click
    expect(notif.reload.in_app_read_at).to be_present
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

  it "does NOT include `data-turbo-confirm` anywhere" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).not_to include("data-turbo-confirm")
  end
end
