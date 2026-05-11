require "rails_helper"

RSpec.describe EntryRowComponent, type: :component do
  describe "rendering" do
    # Calendar refactor 2026-05-11 — the schedule row drops the legacy
    # state column entirely, replaces the glyph prefix with a typed
    # token label (`channel(joined)` / `video(published)` /
    # `game(released)` / `milestone`), and renders an `all day` badge
    # (calendar polish 2026-05-11: bordered box matching the
    # notification-severity-badge — no literal brackets) in the time
    # column for all-day entries. The trailing `[open]` column links
    # straight to the related resource.

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

    it "renders an `all day` badge for all-day entries (not a `—`)" do
      entry = create(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      # Calendar polish 2026-05-11 — the badge text is plain `all day`
      # (no bracketed-text decoration); the surrounding bordered span
      # IS the visual delimiter.
      expect(page).to have_css(".calendar-badge.calendar-badge--all-day", text: "all day")
      expect(page).not_to have_content("[ all day ]")
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

    # Calendar polish 2026-05-11 — the `all day` token renders as a
    # bordered-box badge (same shape as the notification-severity-badge)
    # rather than the legacy `[ all day ]` bracketed-text literal.
    it "the `all day` badge does NOT carry the legacy `[ ... ]` bracket characters" do
      entry = create(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      badge = page.find(".calendar-badge--all-day")
      expect(badge.text.strip).to eq("all day")
      expect(badge.text).not_to include("[")
      expect(badge.text).not_to include("]")
    end

    # 2026-05-12 — the `[remind: t-7 t-1 t-0]` reminder copy was
    # removed along with the `game_release_upcoming` notification
    # kind per user direction. `show_reminder` is kept as an init kwarg
    # for call-site compatibility but is now a no-op.
    it "does NOT render reminder copy on game_release entries (kind dropped)" do
      entry = create(:calendar_entry, :game_release,
                     starts_at: 30.days.from_now,
                     release_precision: :day)
      render_inline(described_class.new(entry: entry, show_reminder: true))
      expect(page).not_to have_content("remind:")
    end
  end
end
