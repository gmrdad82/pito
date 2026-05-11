require "rails_helper"

RSpec.describe EntryRowComponent, type: :component do
  describe "rendering" do
    # Calendar refactor 2026-05-11 — the schedule row drops the legacy
    # state column entirely, replaces the glyph prefix with a typed
    # token label (`channel(joined)` / `video(published)` /
    # `game(released)` / `milestone`), and renders `[ all day ]` in the
    # time column for all-day entries. The trailing `[open]` column
    # links straight to the related resource.

    it "renders a `<month> <dom> <weekday>` date label by default" do
      entry = create(:calendar_entry, :custom, starts_at: Time.zone.parse("2026-05-14 10:00:00 UTC"))
      render_inline(described_class.new(entry: entry))
      # `may 14 thu` — calendar refactor 2026-05-11 format.
      expect(page).to have_content("may 14 thu")
    end

    it "renders the typed label in the type column" do
      entry = create(:calendar_entry, :milestone_manual, title: "podcast")
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("milestone")
      expect(page).to have_content("podcast")
    end

    it "does NOT render the legacy single-letter glyph prefix" do
      entry = create(:calendar_entry, :milestone_manual, title: "podcast")
      render_inline(described_class.new(entry: entry))
      expect(page).not_to have_content(/(?:\A|\s)m:(?:\s|\z)/)
    end

    it "shows time for timed entries" do
      entry = create(:calendar_entry, :custom,
                     all_day: false,
                     starts_at: Time.zone.parse("2026-05-14 14:30:00 UTC"))
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("14:30")
    end

    it "renders a `[ all day ]` badge for all-day entries (not a `—`)" do
      entry = create(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("[ all day ]")
      expect(page).to have_css(".calendar-badge--all-day")
      expect(page).not_to have_content("—")
    end

    it "does NOT render a trailing state column (no `scheduled` / `occurred` cell)" do
      entry = create(:calendar_entry, :custom, :scheduled, title: "x")
      render_inline(described_class.new(entry: entry))
      # The state class still rides on the <tr> for styling, but no
      # explicit text cell exists.
      expect(page).to have_css("tr.calendar-entry--scheduled")
      expect(page).not_to have_css("td", text: /^scheduled$/)
      expect(page).not_to have_css("td", text: /^occurred$/)
    end

    it "leaves the date cell blank when `show_date: false` (group-by-day)" do
      entry = create(:calendar_entry, :custom, starts_at: Time.zone.parse("2026-05-14 10:00:00 UTC"))
      render_inline(described_class.new(entry: entry, show_date: false))
      # The CSS class anchors the cell; assert it carries no text.
      expect(page).to have_css(".calendar-row__date", text: "")
      expect(page).not_to have_content("may 14")
    end

    it "renders ↳ continuation glyph when indented" do
      entry = create(:calendar_entry, :purchase_planned)
      render_inline(described_class.new(entry: entry, indent: true))
      expect(page).to have_content("↳")
    end

    it "renders an `[open]` link in the trailing action column" do
      entry = create(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-row__open a", text: "open")
    end

    it "the `[open]` action targets the related resource for derived entries" do
      v = create(:video)
      entry = create(:calendar_entry, :video_published, video_record: v)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-row__open a[href='/videos/#{v.id}']")
    end

    it "the `[open]` action falls back to the entry show page for free-form types" do
      entry = create(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-row__open a[href='/calendar/entries/#{entry.id}']")
    end

    it "the title link wires the modal-open action with the details_pane URL" do
      entry = create(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-row__title a[data-action*='calendar-entry-modal#open']")
      expect(page).to have_css(".calendar-row__title a[data-calendar-entry-modal-url-param='/calendar/entries/#{entry.id}/details_pane']")
    end

    it "renders [remind: t-7 t-1 t-0] (canonical no-padding form) for future game_release entries when show_reminder is true" do
      entry = create(:calendar_entry, :game_release,
                     starts_at: 30.days.from_now,
                     release_precision: :day)
      render_inline(described_class.new(entry: entry, show_reminder: true))
      expect(page).to have_content("[remind: t-7 t-1 t-0]")
      # Phase 15 reviewer concern 4 — canonical form has no inner spaces.
      expect(page).not_to have_content("[ remind:")
    end

    it "does NOT render the reminder copy for past game_release entries" do
      entry = create(:calendar_entry, :game_release,
                     starts_at: 30.days.ago,
                     release_precision: :day)
      render_inline(described_class.new(entry: entry, show_reminder: true))
      expect(page).not_to have_content("remind:")
    end
  end
end
