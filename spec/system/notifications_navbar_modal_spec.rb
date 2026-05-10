require "rails_helper"

# Layout-level notifications modal (2026-05-10).
#
# The navbar `[notifications]` link opens a modal instead of navigating
# to /notifications. The Stimulus controller (`notifications-modal`) is
# mounted on `<body>`; the dialog and its Turbo Frame live in the
# layout via `shared/_notifications_modal`. rack_test cannot drive the
# JS open / close handshake, but the SSR scaffold is fully assertable:
#   - The body declares the controller alongside `keyboard`.
#   - The navbar link declares the `data-action` open hook.
#   - The navbar link's `href` stays as `/notifications` so JS-off
#     users (and rack_test) get the standalone page as a fallback.
#   - The modal dialog + the wrapping Turbo Frame render once in the
#     layout, regardless of the current page.
RSpec.describe "Notifications navbar modal scaffold", type: :system do
  before { driven_by(:rack_test) }

  it "mounts the notifications-modal Stimulus controller on <body>" do
    visit "/channels"
    expect(page).to have_selector("body[data-controller~='notifications-modal']", visible: :all)
  end

  it "renders the layout-level <dialog id='notifications-modal'>" do
    visit "/channels"
    expect(page).to have_selector("dialog#notifications-modal", visible: :all)
  end

  it "renders the layout-level <turbo-frame id='notifications_modal_frame'>" do
    visit "/channels"
    expect(page).to have_selector("dialog#notifications-modal turbo-frame#notifications_modal_frame", visible: :all)
  end

  it "renders a `[close]` button inside the dialog with the close action wired" do
    visit "/channels"
    close_btn = find("dialog#notifications-modal button.bracketed", text: "close", visible: :all)
    expect(close_btn["data-action"].to_s).to include("notifications-modal#close")
  end

  it "renders the modal once even on the standalone /notifications page" do
    visit "/notifications"
    expect(page).to have_selector("dialog#notifications-modal", visible: :all, count: 1)
    expect(page).to have_selector("dialog#notifications-modal turbo-frame#notifications_modal_frame", visible: :all, count: 1)
  end

  it "navbar [notifications] link declares the modal-open Stimulus action" do
    visit "/channels"
    link = find("header a.bracketed", text: /notifications|N/, visible: :all, match: :first)
    expect(link["data-action"].to_s).to include("click->notifications-modal#open")
  end

  it "navbar [notifications] link href falls back to /notifications" do
    visit "/channels"
    link = find("header a.bracketed", text: /notifications|N/, visible: :all, match: :first)
    expect(link[:href]).to eq(notifications_path)
  end

  it "footer [notifications] link also declares the modal-open Stimulus action" do
    visit "/channels"
    link = find("footer a.bracketed[href='#{notifications_path}']", visible: :all)
    expect(link["data-action"].to_s).to include("click->notifications-modal#open")
  end

  it "navbar [notifications] still works as a full-page navigation (JS-off fallback)" do
    visit "/channels"
    find("header a.bracketed", text: /notifications|N/, visible: :all, match: :first).click
    # rack_test follows the href; the standalone page renders.
    expect(page).to have_selector("h1", text: "notifications")
    expect(page).to have_current_path("/notifications")
  end

  it "does NOT include `data-turbo-confirm` anywhere in the layout modal scaffold" do
    visit "/channels"
    # Scope the assertion to the dialog only — the rest of the page
    # may legitimately use `data-turbo-confirm` (none does today, but
    # this spec is about the modal scaffold).
    dialog_html = find("dialog#notifications-modal", visible: :all).native.to_s
    expect(dialog_html).not_to include("data-turbo-confirm")
  end

  it "does NOT call window.confirm / alert / prompt inside the layout modal scaffold" do
    visit "/channels"
    dialog_html = find("dialog#notifications-modal", visible: :all).native.to_s
    expect(dialog_html).not_to match(/window\.(confirm|alert|prompt)\(/)
  end
end
