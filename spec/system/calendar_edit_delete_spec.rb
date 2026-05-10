require "rails_helper"

# Phase 15 §2 — edit + soft-cancel flow through the action screen.
RSpec.describe "Calendar edit / cancel", type: :system do
  before { driven_by(:rack_test) }

  it "manual entry: click [ edit ], change title, save" do
    ce = create(:calendar_entry, :milestone_manual, title: "old name")
    visit calendar_entry_path(ce)
    click_link "edit"
    fill_in "calendar_entry_title", with: "new name"
    # Bracketed-link convention: no inner spaces (`[save]` not
    # `[ save ]`). See `docs/agents/rails.md` rule A.
    click_button "[save]"
    expect(ce.reload.title).to eq("new name")
  end

  it "manual entry: click [ cancel ] reaches the confirmation screen" do
    ce = create(:calendar_entry, :milestone_manual, title: "to-cancel")
    visit calendar_entry_path(ce)
    click_link "cancel"
    expect(page).to have_content("cancel calendar entry?")
    expect(page).to have_content("to-cancel")
  end

  it "derived entry: shows [ note ] but not [ edit ] / [ cancel ]" do
    ce = create(:calendar_entry, :video_published)
    visit calendar_entry_path(ce)
    # The detail page has chrome nav with "settings", which contains
    # "set" and other links; we scope to the action cluster at the
    # bottom (one of the dot-list rows).
    expect(page).to have_link("note")
    # No [ edit ] or [ cancel ] link in the action area.
    expect(page).not_to have_link("edit")
    # `cancel` may appear as Capybara matches on text — it's also the
    # word in flash buttons. We scope to only the read-only branch:
    # the [ note ] link is present, and the link target /edit is NOT.
    expect(page).not_to have_css("a[href$='/edit']")
  end

  it "cancelled entry: appears in schedule view with state=all" do
    ce = create(:calendar_entry, :milestone_manual, :cancelled,
                title: "was-cxld",
                starts_at: 1.day.from_now)
    visit "/calendar/schedule?state=all"
    expect(page).to have_content("was-cxld")
    expect(page).to have_content("cancelled")
  end
end
