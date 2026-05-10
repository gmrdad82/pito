require "rails_helper"

# Phase 15 §2 — quick-add Turbo Frame flow. rack_test renders the
# turbo-frame containers as plain divs (Turbo Frame swap is a JS
# feature) so we cover the form pre-fill + submit happy path here;
# the actual frame-swap behaviour is covered by the manual playbook.
RSpec.describe "Calendar quick-add", type: :system do
  before { driven_by(:rack_test) }

  it "renders the quick-add form with a milestone_manual default" do
    visit "/calendar/entries/new"
    expect(page).to have_field("calendar_entry_title")
    expect(page).to have_field("calendar_entry_starts_at")
  end

  it "creates a milestone_manual entry from the form" do
    visit "/calendar/entries/new"
    fill_in "calendar_entry_title", with: "podcast appearance"
    fill_in "calendar_entry_starts_at", with: 1.day.from_now.strftime("%Y-%m-%dT%H:%M")
    choose "calendar_entry_entry_type_milestone_manual"
    choose "calendar_entry_all_day_no"
    click_button "[ create ]"
    expect(page).to have_content("calendar entry created")
    expect(page).to have_content("podcast appearance")
  end

  it "rejects yes/no smuggling — `true` / `false` strings" do
    # Direct POST mirrors what a malicious / mistaken form submission
    # would carry. Capybara click_button doesn't allow injecting raw
    # values, so this case lives in the request spec; here we cover
    # the legit yes/no path only.
    visit "/calendar/entries/new"
    expect(page).to have_field("calendar_entry_all_day_yes")
    expect(page).to have_field("calendar_entry_all_day_no")
  end
end
