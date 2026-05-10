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

  it "click the [all] master toggle while currently checked clears all 5 (empty types=)" do
    visit "/calendar/schedule"
    find("a.filter-chip[data-keyboard-filter-chip='all']").click
    expect(page.current_url).to match(/types=(?:&|$)/)
  end

  it "click [include cancelled] surfaces cancelled entries" do
    visit "/calendar/schedule"
    find("a.filter-chip[data-keyboard-filter-chip='include cancelled']").click
    expect(page.current_url).to include("state=all")
  end

  it "[<current-month>] in the breadcrumb links to the canonical month URL" do
    # Phase 15 calendar UX restructure — breadcrumb segment flip
    # (2026-05-10). The breadcrumb's middle segment is the
    # current-month label (e.g. `[may 2026]`) and is the toggle link
    # back to the month grid. The active-view label is the trailing
    # `[schedule]` segment, rendered as plain text.
    #
    # The toggle targets `/calendar/month/<year>/<month>` directly
    # (not `/calendar`, which is the view-persistence router). Routing
    # through the router would let a stale `pito-calendar-view`
    # localStorage value redirect the user back to schedule, making
    # the click look broken to the user.
    visit "/calendar/schedule"
    now = Time.current
    month_label = Date.new(now.year, now.month, 1).strftime("%b %Y").downcase
    within("nav.dot-list") do
      click_link month_label
    end
    expect(page).to have_current_path(
      "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
    )
  end

  it "[+] in the breadcrumb actions submits the default-create form (POST /calendar/entries)" do
    # `[+]` is a `button_to` default-create (Projects pattern); the
    # controller seeds an "Untitled event" milestone_manual entry and
    # redirects to /edit. Capybara's `click_button "+"` submits the
    # surrounding form.
    visit "/calendar/schedule"
    expect {
      within("nav.dot-list") { click_button "+" }
    }.to change { CalendarEntry.count }.by(1)
    expect(page.current_path).to match(%r{\A/calendar/entries/\d+/edit\z})
  end
end
