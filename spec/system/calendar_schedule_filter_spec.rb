require "rails_helper"

# Phase 15 §2 — schedule view filter cluster.
RSpec.describe "Calendar schedule filters", type: :system do
  before { driven_by(:rack_test) }

  it "click [ video ] navigates to ?type=video" do
    visit "/calendar/schedule"
    # The chrome nav has "videos" (plural); the filter cluster has
    # "video" (singular). Scope to the filter cluster to avoid the
    # ambiguous-match.
    within("[data-controller='calendar-filter']") do
      click_link "video"
    end
    expect(page.current_url).to include("type=video")
  end

  it "click [ all types ] resets the filter" do
    visit "/calendar/schedule?type=video"
    within("[data-controller='calendar-filter']") do
      click_link "all types"
    end
    expect(page.current_url).to include("/calendar/schedule")
    expect(page.current_url).not_to include("type=video")
  end

  it "click [ include cancelled ] surfaces cancelled entries" do
    visit "/calendar/schedule"
    click_link "include cancelled"
    expect(page.current_url).to include("state=all")
  end
end
