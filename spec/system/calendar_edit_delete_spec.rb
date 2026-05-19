require "rails_helper"

# Phase 15 §2 — edit + soft-cancel flow through the action screen.
RSpec.describe "Calendar edit / cancel", type: :system do
  before { driven_by(:rack_test) }

  it "manual entry: click [ edit ], change title, save" do
    skip "TODO: revisit when /calendar back in scope (paused 2026-05-19)"
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
    skip "TODO: revisit when /calendar back in scope (paused 2026-05-19)"
    ce = create(:calendar_entry, :milestone_manual, title: "to-cancel")
    visit calendar_entry_path(ce)
    click_link "cancel"
    expect(page).to have_content("cancel calendar entry?")
    expect(page).to have_content("to-cancel")
  end

  it "derived entry: hides [ edit ] / [ cancel ] (read-only)" do
    skip "TODO: revisit when /calendar back in scope (paused 2026-05-19)"
    ce = create(:calendar_entry, :video_published)
    visit calendar_entry_path(ce)
    # Phase 15 reviewer concern 6 (per `entries/show.html.erb`) — the
    # `[note]` link was removed because the note modal markup is not
    # yet rendered on this page. PATCH /calendar/entries/:id/note
    # stays in place for MCP / Rust callers; the UI affordance will
    # come back when the modal is built. So a derived entry's action
    # area on the web has only `[back]` — no `[edit]`, no `[cancel]`,
    # and currently no `[note]` either.
    expect(page).not_to have_link("edit")
    expect(page).not_to have_css("a[href$='/edit']")
    expect(page).not_to have_link("note")
    # `[back]` survives as the only action.
    expect(page).to have_link("back")
  end

  it "cancelled entry: appears in schedule view with state=all" do
    skip "TODO: revisit when /calendar back in scope (paused 2026-05-19)"
    ce = create(:calendar_entry, :milestone_manual, :cancelled,
                title: "was-cxld",
                starts_at: 1.day.from_now)
    visit "/calendar/schedule?state=all"
    expect(page).to have_content("was-cxld")
    expect(page).to have_content("cancelled")
  end
end
