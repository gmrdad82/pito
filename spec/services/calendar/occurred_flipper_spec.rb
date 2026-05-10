require "rails_helper"

RSpec.describe Calendar::OccurredFlipper do
  describe ".flip_ripe!" do
    it "flips :scheduled entries with starts_at in the past to :occurred" do
      ripe = create(:calendar_entry, :custom, starts_at: 1.hour.ago, state: :scheduled)
      described_class.flip_ripe!
      expect(ripe.reload.state).to eq("occurred")
    end

    it "leaves :scheduled entries with future starts_at alone" do
      future = create(:calendar_entry, :custom, starts_at: 1.day.from_now, state: :scheduled)
      described_class.flip_ripe!
      expect(future.reload.state).to eq("scheduled")
    end

    it "does NOT flip :cancelled entries even if past" do
      cancelled = create(:calendar_entry, :custom, starts_at: 1.hour.ago, state: :cancelled)
      described_class.flip_ripe!
      expect(cancelled.reload.state).to eq("cancelled")
    end

    it "does NOT flip :superseded entries even if past" do
      superseded = create(:calendar_entry, :custom, starts_at: 1.hour.ago, state: :superseded)
      described_class.flip_ripe!
      expect(superseded.reload.state).to eq("superseded")
    end

    it "does NOT flip :occurred entries (no-op)" do
      occurred = create(:calendar_entry, :custom, starts_at: 2.days.ago, state: :occurred)
      described_class.flip_ripe!
      expect(occurred.reload.state).to eq("occurred")
    end
  end
end
