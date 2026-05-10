require "rails_helper"

# Phase 15 §2 — schedule view filter cluster (calendar UX restructure).
RSpec.describe "Calendar schedule filters", type: :system do
  before { driven_by(:rack_test) }

  it "click the [video] chip toggles ?types into the URL" do
    visit "/calendar/schedule"
    # The chrome nav has "videos" (plural); the filter chip carries
    # `data-keyboard-filter-chip="video"` (singular). Find and click
    # the chip directly via that hook to avoid ambiguous-match across
    # the page chrome.
    find("a.filter-chip[data-keyboard-filter-chip='video']").click
    # From the default "all checked" state, clicking [video] flips it
    # off, so the URL carries the complement (the other 4 kinds).
    expect(page.current_url).to include("types=")
    expect(page.current_url).not_to match(/types=([^&]*,)?video(,|$)/)
  end

  it "click the [all types] master toggle while currently checked clears all 5 (empty types=)" do
    visit "/calendar/schedule"
    find("a.filter-chip[data-keyboard-filter-chip='all types']").click
    expect(page.current_url).to match(/types=(?:&|$)/)
  end

  it "click [include cancelled] surfaces cancelled entries" do
    visit "/calendar/schedule"
    click_link "include cancelled"
    expect(page.current_url).to include("state=all")
  end

  it "[month] in the breadcrumb actions links back to /calendar" do
    visit "/calendar/schedule"
    within("nav.dot-list") do
      click_link "month"
    end
    expect(page).to have_current_path("/calendar")
  end

  it "[+] in the breadcrumb actions links to the new entry form" do
    visit "/calendar/schedule"
    within("nav.dot-list") do
      click_link "+"
    end
    expect(page).to have_current_path("/calendar/entries/new")
  end
end
