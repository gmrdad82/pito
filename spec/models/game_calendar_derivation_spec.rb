require "rails_helper"

RSpec.describe Game, type: :model do
  describe "game → calendar_entry derivation" do
    # Phase 14 (Game/IGDB sync) hasn't shipped at the time of Phase 15
    # implementation. The CalendarDerivable hooks on Game guard with
    # `respond_to?(:release_date)` so the host model boots cleanly. The
    # spec below verifies the no-op contract while the column is absent.
    let(:phase_14_ready?) { Game.column_names.include?("release_date") }

    it "is a no-op on Game.create when release_date column is absent (Phase 14 not shipped)" do
      next if phase_14_ready?

      expect {
        create(:game)
      }.not_to change { CalendarEntry.where(entry_type: :game_release).count }
    end
  end
end
