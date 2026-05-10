require "rails_helper"

RSpec.describe Game, type: :model do
  describe "game → calendar_entry derivation" do
    # Phase 14 (Game/IGDB sync) hasn't shipped at the time of Phase 15
    # implementation. The CalendarDerivable hooks on Game guard with
    # `respond_to?(:release_date)` so the host model boots cleanly. The
    # specs below skip until that column exists.
    let(:phase_14_ready?) { Game.column_names.include?("release_date") }

    it "writes a game_release entry when release_date is set for the first time" do
      skip "Phase 14 release_date column not present" unless phase_14_ready?

      g = create(:game)
      g.update!(release_date: 30.days.from_now)
      ce = CalendarEntry.where(game_id: g.id, entry_type: :game_release).first
      expect(ce).to be_present
    end

    it "supersedes the entry when release_date is cleared" do
      skip "Phase 14 release_date column not present" unless phase_14_ready?

      g = create(:game, release_date: 30.days.from_now)
      ce = CalendarEntry.where(game_id: g.id, entry_type: :game_release).first
      expect(ce).to be_present
      g.update!(release_date: nil)
      expect(ce.reload.state).to eq("superseded")
    end

    it "re-derives on title change, overwriting the entry's title" do
      skip "Phase 14 release_date column not present" unless phase_14_ready?

      g = create(:game, title: "Old Title")
      g.update!(release_date: 30.days.from_now)
      ce = CalendarEntry.where(game_id: g.id, entry_type: :game_release).first
      expect(ce.title).to eq("released: Old Title")

      g.update!(title: "New Title")
      expect(ce.reload.title).to eq("released: New Title")
    end

    it "preserves starts_at when manual_date_override=true on IGDB-driven re-sync" do
      # Phase 14 owns the IGDB re-sync flow. Phase 15 only ships the
      # column + the Game-side hook contract; the override semantics
      # live in the IGDB sync flow itself.
      skip "Phase 14 IGDB sync flow not implemented"
    end

    it "cascades the calendar entry on Game.destroy" do
      skip "Phase 14 release_date column not present" unless phase_14_ready?

      g = create(:game)
      g.update!(release_date: 30.days.from_now)
      expect(CalendarEntry.where(game_id: g.id).count).to eq(1)
      expect { g.destroy }.to change { CalendarEntry.where(game_id: g.id).count }.by(-1)
    end

    it "is a no-op on Game.create when release_date column is absent (Phase 14 not shipped)" do
      next if phase_14_ready?

      expect {
        create(:game)
      }.not_to change { CalendarEntry.where(entry_type: :game_release).count }
    end
  end
end
