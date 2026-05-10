require "rails_helper"

# Phase 15 §2 — Capybara system spec for the month grid navigation.
#
# rack_test driver doesn't fire JS, so keyboard-shortcut bindings
# (`[`, `]`, `t`) are exercised by the JS controller spec / manual
# playbook. These specs cover the click-through nav links.
RSpec.describe "Calendar month navigation", type: :system do
  before { driven_by(:rack_test) }

  it "click [prev] from May 2026 lands on April 2026" do
    visit "/calendar/month/2026/05"
    click_link "prev"
    expect(page).to have_current_path("/calendar/month/2026/04")
  end

  it "click [next] from December 2025 lands on January 2026" do
    visit "/calendar/month/2025/12"
    click_link "next"
    expect(page).to have_current_path("/calendar/month/2026/01")
  end

  it "click [today] from a past month lands on the calendar root" do
    visit "/calendar/month/2024/01"
    expect(page).to have_link("today")
    click_link "today"
    # `/calendar` is now a JS-router shell; rack_test follows the
    # meta-refresh fallback to the current month grid only when JS
    # is enabled. The click_link landing on /calendar is sufficient
    # to prove the [today] anchor wiring.
    expect(page).to have_current_path("/calendar")
  end

  it "[today] is suppressed on the current month" do
    now = Time.current
    visit "/calendar/month/#{now.year}/#{now.month}"
    expect(page).not_to have_link("today")
  end

  it "[schedule] in the breadcrumb actions links to the schedule view" do
    visit "/calendar/month/2026/05"
    within("nav.dot-list") do
      click_link "schedule"
    end
    expect(page).to have_current_path("/calendar/schedule")
  end

  it "[+] in the breadcrumb actions links to the new entry form" do
    visit "/calendar/month/2026/05"
    within("nav.dot-list") do
      click_link "+"
    end
    expect(page).to have_current_path("/calendar/entries/new")
  end
end
