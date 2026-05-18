require "rails_helper"

RSpec.describe EntryChipComponent, type: :component do
  describe "rendering" do
    # Calendar refactor 2026-05-11 — the chip no longer shows the
    # legacy single-letter glyph prefix (`c:` / `v:` / `g:` / ...). It
    # now renders a typed token label like `channel(joined)` /
    # `video(published)` / `game(released)` / `milestone`. The chip
    # itself is a click target for the layout-level details modal.

    it "renders the typed label for a milestone_manual entry" do
      entry = build_stubbed(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("milestone")
    end

    it "renders the typed label for a video_published entry" do
      entry = build_stubbed(:calendar_entry, :video_published)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("video(published)")
    end

    it "renders the typed label for a game_release entry" do
      entry = build_stubbed(:calendar_entry, :game_release)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("game(released)")
    end

    it "renders the typed label for a channel_published entry" do
      # create needed: the spec queries the DB for the channel_published
      # CalendarEntry that the Channel after_create callback materializes.
      ch = create(:channel)
      entry = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("channel(joined)")
    end

    it "does NOT render the legacy single-letter glyph prefix" do
      entry = build_stubbed(:calendar_entry, :milestone_manual, title: "podcast")
      render_inline(described_class.new(entry: entry))
      expect(page).not_to have_content(/(?:\A|\s)m:(?:\s|\z)/)
      expect(page).not_to have_content(/(?:\A|\s)~:/)
    end

    it "shows the title" do
      entry = build_stubbed(:calendar_entry, :milestone_manual, title: "podcast appearance")
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("podcast appearance")
    end

    it "truncates long titles to 24 chars + ellipsis" do
      long = "a" * 50
      entry = build_stubbed(:calendar_entry, :milestone_manual, title: long)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("a" * 24 + "…")
    end

    it "applies the state-specific class for occurred" do
      entry = build_stubbed(:calendar_entry, :custom, :occurred)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-entry--occurred")
    end

    it "applies the state-specific class for cancelled" do
      entry = build_stubbed(:calendar_entry, :custom, :cancelled)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-entry--cancelled")
    end

    it "omits the time portion for all-day entries" do
      entry = build_stubbed(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      # No "HH:MM" stamp.
      expect(page.text).not_to match(/\d{2}:\d{2}/)
    end

    it "shows HH:MM for timed entries" do
      entry = build_stubbed(:calendar_entry, :custom,
                            all_day: false,
                            starts_at: Time.zone.parse("2026-05-15 14:30:00 UTC"))
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("14:30")
    end

    # The chip's click handler opens the modal; the underlying `href`
    # stays a JS-off fallback to the entry show page. The wire-up
    # carries the Stimulus action + the details_pane URL on a param.
    it "wires the modal-open action with the details_pane URL on the click element" do
      entry = build_stubbed(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css("a[data-action*='calendar-entry-modal#open']")
      expect(page).to have_css("a[data-calendar-entry-modal-url-param='/calendar/entries/#{entry.id}/details_pane']")
    end

    it "falls back to the entry show page as the link href (JS-off path)" do
      entry = build_stubbed(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css("a[href='/calendar/entries/#{entry.id}']")
    end
  end
end
