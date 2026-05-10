require "rails_helper"

# Phase 16 §3 UX restructure 2026-05-10 — open notification detail in a modal.
#
# rack_test cannot drive the Stimulus `notification-modal` controller
# (no JS), but the SSR scaffold IS testable: the dialog mount, the
# Turbo Frame inside it, and the row link's wiring all render server-
# side. Live open/close is covered by manual playbook.
RSpec.describe "Notifications modal", type: :system do
  before { driven_by(:rack_test) }

  it "renders a single notification-detail dialog at the bottom of the index" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_selector('dialog[data-notification-modal-target="dialog"]', visible: :all, count: 1)
  end

  it "renders the notification_detail_frame Turbo Frame inside the dialog" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_selector('dialog[data-notification-modal-target="dialog"] turbo-frame#notification_detail_frame', visible: :all)
  end

  it "row link declares the modal-open Stimulus action" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    row_link = find("a##{ActionView::RecordIdentifier.dom_id(notif)} a, a.notification-title", match: :first)
    expect(row_link["data-action"].to_s).to include("click->notification-modal#open")
  end

  it "row link href falls back to the canonical show path" do
    notif = create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_link(href: notification_path(notif))
  end

  it "show page wraps its body in the matching Turbo Frame" do
    notif = create(:notification, :video_published)
    visit "/notifications/#{notif.id}"
    expect(page).to have_selector('turbo-frame#notification_detail_frame', visible: :all)
  end

  it "modal `[ back ]` carries the modal-close Stimulus action" do
    notif = create(:notification, :video_published)
    visit "/notifications/#{notif.id}"
    back_link = find("a", text: "back")
    expect(back_link["data-action"].to_s).to include("click->notification-modal#close")
    expect(back_link[:href]).to eq(notifications_path)
  end

  it "does NOT include `data-turbo-confirm` anywhere in the modal scaffold" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page.body).not_to include("data-turbo-confirm")
  end
end
