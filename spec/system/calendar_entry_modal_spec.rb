require "rails_helper"

# Calendar refactor 2026-05-11 — click-to-open details modal for
# calendar entries. The month grid chip + schedule list title both
# wire `click->calendar-entry-modal#open` and carry the entry's
# `/calendar/entries/:id/details_pane` URL on a Stimulus param.
#
# rack_test cannot drive the controller (no JS), but the SSR scaffold
# — the dialog mount, the inner Turbo Frame, the trigger wiring, and
# the details_pane fragment itself — IS testable. Live open/close is
# covered by manual playbook.
RSpec.describe "Calendar entry modal (SSR scaffold)", type: :system do
  before { driven_by(:rack_test) }

  it "month grid mounts a single calendar-entry-modal dialog" do
    AppSetting.delete_all
    AppSetting.create!(key: "tz_seed", value: "x", timezone: "UTC")
    create(:calendar_entry, :milestone_manual,
           starts_at: Time.zone.local(2026, 5, 15, 12, 0))
    visit "/calendar/month/2026/05"
    expect(page).to have_selector('dialog[data-calendar-entry-modal-target="dialog"]', visible: :all, count: 1)
  end

  it "month grid: dialog hosts the calendar_entry_modal_frame Turbo Frame" do
    create(:calendar_entry, :milestone_manual,
           starts_at: Time.zone.local(2026, 5, 15, 12, 0))
    visit "/calendar/month/2026/05"
    expect(page).to have_selector(
      'dialog[data-calendar-entry-modal-target="dialog"] turbo-frame#calendar_entry_modal_frame',
      visible: :all
    )
  end

  it "month grid: chip wires the modal-open Stimulus action with the details_pane URL" do
    AppSetting.delete_all
    AppSetting.create!(key: "tz_seed", value: "x", timezone: "UTC")
    ce = create(:calendar_entry, :milestone_manual,
                starts_at: Time.zone.local(2026, 5, 15, 12, 0),
                title: "podcast")
    visit "/calendar/month/2026/05"
    chip = find("a.calendar-entry-chip", match: :first)
    expect(chip["data-action"].to_s).to include("click->calendar-entry-modal#open")
    expect(chip["data-calendar-entry-modal-url-param"]).to eq("/calendar/entries/#{ce.id}/details_pane")
  end

  it "month grid: chip fallback href is the entry show page (JS-off path)" do
    ce = create(:calendar_entry, :milestone_manual,
                starts_at: Time.zone.local(2026, 5, 15, 12, 0))
    visit "/calendar/month/2026/05"
    chip = find("a.calendar-entry-chip", match: :first)
    expect(chip[:href]).to eq("/calendar/entries/#{ce.id}")
  end

  it "schedule list mounts a single calendar-entry-modal dialog" do
    create(:calendar_entry, :milestone_manual, starts_at: 1.day.from_now)
    visit "/calendar/schedule"
    expect(page).to have_selector('dialog[data-calendar-entry-modal-target="dialog"]', visible: :all, count: 1)
  end

  it "schedule list: title link wires the modal-open Stimulus action" do
    ce = create(:calendar_entry, :milestone_manual,
                starts_at: 1.day.from_now,
                title: "podcast")
    visit "/calendar/schedule"
    title_link = find(".calendar-row__title a", match: :first)
    expect(title_link["data-action"].to_s).to include("click->calendar-entry-modal#open")
    expect(title_link["data-calendar-entry-modal-url-param"]).to eq("/calendar/entries/#{ce.id}/details_pane")
  end

  it "details_pane fragment wraps its body in the matching Turbo Frame" do
    ce = create(:calendar_entry, :milestone_manual, title: "podcast")
    visit "/calendar/entries/#{ce.id}/details_pane"
    expect(page).to have_selector('turbo-frame#calendar_entry_modal_frame', visible: :all)
  end

  it "details_pane renders the typed label + entry title + close button" do
    ce = create(:calendar_entry, :milestone_manual, title: "podcast")
    visit "/calendar/entries/#{ce.id}/details_pane"
    expect(page).to have_content("milestone")
    expect(page).to have_content("podcast")
    close_link = find("a", text: "close")
    expect(close_link["data-action"].to_s).to include("click->calendar-entry-modal#close")
  end

  it "details_pane shows the `all day` badge for all-day entries" do
    ce = create(:calendar_entry, :game_release, all_day: true)
    visit "/calendar/entries/#{ce.id}/details_pane"
    # Calendar polish 2026-05-11 — bordered-box badge, no literal
    # brackets around the text. 2026-05-11 sweep migrated rendering to
    # the shared `StatusBadgeComponent`; canonical class is
    # `.status-badge.status-badge--all_day`.
    expect(page).to have_css(".status-badge.status-badge--all_day", text: "all day")
    expect(page).not_to have_content("[ all day ]")
  end

  it "details_pane `[open video]` link points at the related video" do
    v = create(:video)
    ce = create(:calendar_entry, :video_published, video_record: v)
    visit "/calendar/entries/#{ce.id}/details_pane"
    open_link = find("a", text: "open video")
    expect(open_link[:href]).to eq("/videos/#{v.id}")
  end

  it "scaffold does NOT include `data-turbo-confirm` anywhere" do
    create(:calendar_entry, :milestone_manual,
           starts_at: Time.zone.local(2026, 5, 15, 12, 0))
    visit "/calendar/month/2026/05"
    expect(page.body).not_to include("data-turbo-confirm")
  end
end
