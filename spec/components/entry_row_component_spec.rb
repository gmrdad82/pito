require "rails_helper"

RSpec.describe EntryRowComponent, type: :component do
  describe "rendering" do
    it "renders a date label" do
      entry = create(:calendar_entry, :custom, starts_at: Time.zone.parse("2026-05-14 10:00:00 UTC"))
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("may 14")
    end

    it "renders the prefix glyph + title" do
      entry = create(:calendar_entry, :milestone_manual, title: "podcast")
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("m:")
      expect(page).to have_content("podcast")
    end

    it "shows time for timed entries" do
      entry = create(:calendar_entry, :custom,
                     all_day: false,
                     starts_at: Time.zone.parse("2026-05-14 14:30:00 UTC"))
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("14:30")
    end

    it "shows — for all-day entries" do
      entry = create(:calendar_entry, :game_release, all_day: true)
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("—")
    end

    it "renders the state label" do
      entry = create(:calendar_entry, :custom, :scheduled, title: "x")
      render_inline(described_class.new(entry: entry))
      expect(page).to have_content("scheduled")
    end

    it "renders ↳ continuation glyph when indented" do
      entry = create(:calendar_entry, :purchase_planned)
      render_inline(described_class.new(entry: entry, indent: true))
      expect(page).to have_content("↳")
    end

    it "renders [ remind: t-7 t-1 t-0 ] for future game_release entries when show_reminder is true" do
      entry = create(:calendar_entry, :game_release,
                     starts_at: 30.days.from_now,
                     release_precision: :day)
      render_inline(described_class.new(entry: entry, show_reminder: true))
      expect(page).to have_content("remind:")
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
