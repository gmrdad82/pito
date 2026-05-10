require "rails_helper"

RSpec.describe EntryChipComponent, type: :component do
  describe "rendering" do
    it "shows the prefix glyph for a milestone_manual entry" do
      entry = create(:calendar_entry, :milestone_manual)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("m:")
    end

    it "shows the prefix glyph for a video_published entry" do
      entry = create(:calendar_entry, :video_published)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("v:")
    end

    it "shows the title" do
      entry = create(:calendar_entry, :milestone_manual, title: "podcast appearance")
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("podcast appearance")
    end

    it "truncates long titles to 24 chars + ellipsis" do
      long = "a" * 50
      entry = create(:calendar_entry, :milestone_manual, title: long)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("a" * 24 + "…")
    end

    it "applies the state-specific class for occurred" do
      entry = create(:calendar_entry, :custom, :occurred)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-entry--occurred")
    end

    it "applies the state-specific class for cancelled" do
      entry = create(:calendar_entry, :custom, :cancelled)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css(".calendar-entry--cancelled")
    end

    it "omits the time portion for all-day entries" do
      entry = create(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      # No "HH:MM" stamp.
      expect(page.text).not_to match(/\d{2}:\d{2}/)
    end

    it "shows HH:MM for timed entries" do
      entry = create(:calendar_entry, :custom,
                     all_day: false,
                     starts_at: Time.zone.parse("2026-05-15 14:30:00 UTC"))
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("14:30")
    end

    it "links a video_published entry to /videos/:id" do
      v = create(:video)
      entry = create(:calendar_entry, :video_published, video_record: v)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css("a[href='/videos/#{v.id}']")
    end

    it "links a channel_published entry to /channels/:id" do
      # `create(:channel)` already triggers the auto-derive callback
      # which writes a `channel_published` entry. Re-use that entry
      # rather than constructing a duplicate (which would collide on
      # the partial unique index).
      ch = create(:channel)
      entry = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      expect(entry).to be_present
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css("a[href='/channels/#{ch.id}']")
    end

    it "links a game_release entry to /games/:id" do
      g = create(:game)
      entry = create(:calendar_entry, :game_release, game: g)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_css("a[href='/games/#{g.id}']")
    end
  end
end
