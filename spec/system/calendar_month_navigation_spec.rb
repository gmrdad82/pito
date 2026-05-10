require "rails_helper"

# Phase 15 §2 — Capybara system spec for the month grid navigation.
#
# rack_test driver doesn't fire JS, so keyboard-shortcut bindings
# (`[`, `]`, `t`) are exercised by the JS controller spec / manual
# playbook. These specs cover the click-through nav links.
RSpec.describe "Calendar month navigation", type: :system do
  before { driven_by(:rack_test) }

  it "click [ prev month ] from May 2026 lands on April 2026" do
    visit "/calendar/month/2026/05"
    click_link "prev month"
    expect(page).to have_current_path("/calendar/month/2026/04")
  end

  it "click [ next month ] from December 2025 lands on January 2026" do
    visit "/calendar/month/2025/12"
    click_link "next month"
    expect(page).to have_current_path("/calendar/month/2026/01")
  end

  it "click [ today ] from a past month lands on the current month" do
    visit "/calendar/month/2024/01"
    expect(page).to have_link("today")
    click_link "today"
    now = Time.current
    expect(page).to have_current_path("/calendar/month/#{now.year}/#{now.month}")
  end

  it "[ today ] is suppressed on the current month" do
    now = Time.current
    visit "/calendar/month/#{now.year}/#{now.month}"
    expect(page).not_to have_link("today")
  end
end
