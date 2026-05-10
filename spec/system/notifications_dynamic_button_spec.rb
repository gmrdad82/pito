require "rails_helper"

# Phase 16 §3 UX restructure 2026-05-10 — dynamic [mark all as read] button.
#
# Capybara :rack_test cannot exercise the JS controller that swaps the
# button label and form action. The spec asserts the SSR scaffolding so
# the controller has everything it needs at boot time:
#
#   - The wrapper element carries the controller registration AND the
#     three values the controller reads (mark-all URL, mark-read URL,
#     total-unread count).
#   - The form carries the `notifications-dynamic-button-target="form"`
#     hook so the controller can mutate `form.action`.
#   - The label span carries the `notifications-dynamic-button-target="label"`
#     hook so the controller can mutate `label.textContent`.
#
# JS-driven counter behaviour is exercised manually per the playbook.
RSpec.describe "Notifications dynamic mark-read button", type: :system do
  before { driven_by(:rack_test) }

  it "mounts the bulk-select + notifications-dynamic-button controllers" do
    create(:notification, :video_published)
    visit "/notifications"
    wrapper = find('[data-controller~="notifications-dynamic-button"]')
    expect(wrapper["data-controller"]).to include("bulk-select")
    expect(wrapper["data-controller"]).to include("notifications-dynamic-button")
  end

  it "wires mark-all and mark-read URLs onto the wrapper" do
    create(:notification, :video_published)
    visit "/notifications"
    wrapper = find('[data-controller~="notifications-dynamic-button"]')
    expect(wrapper["data-notifications-dynamic-button-mark-all-url-value"])
      .to eq("/notifications/mark_all_read")
    expect(wrapper["data-notifications-dynamic-button-mark-read-url-value"])
      .to eq("/notifications/mark_read")
  end

  it "publishes the unread total onto the wrapper" do
    create_list(:notification, 3, :video_published)
    visit "/notifications"
    wrapper = find('[data-controller~="notifications-dynamic-button"]')
    expect(wrapper["data-notifications-dynamic-button-total-unread-value"]).to eq("3")
  end

  it "exposes the form and label as Stimulus targets" do
    create(:notification, :video_published)
    visit "/notifications"
    expect(page).to have_selector('form[data-notifications-dynamic-button-target="form"]', visible: :all)
    expect(page).to have_selector('span[data-notifications-dynamic-button-target="label"]', text: "mark all as read")
  end

  it "default form action is /notifications/mark_all_read" do
    create(:notification, :video_published)
    visit "/notifications"
    form = find('form[data-notifications-dynamic-button-target="form"]', visible: :all)
    expect(form["action"]).to eq("/notifications/mark_all_read")
  end

  it "hides the button entirely when there are no unread rows" do
    create(:notification, :read, :video_published)
    visit "/notifications"
    expect(page).not_to have_selector('form[data-notifications-dynamic-button-target="form"]', visible: :all)
    expect(page).not_to have_button("[mark all as read]")
  end
end
