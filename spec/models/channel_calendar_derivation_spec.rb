require "rails_helper"

RSpec.describe Channel, type: :model do
  describe "channel → calendar_entry derivation" do
    it "writes a channel_published entry on create, keyed on created_at" do
      ch = create(:channel)
      ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      expect(ce).to be_present
      expect(ce.starts_at).to be_within(1.second).of(ch.created_at)
      expect(ce.all_day).to be(true)
    end

    it "does NOT re-derive on irrelevant attribute changes" do
      ch = create(:channel)
      ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      original_updated_at = ce.updated_at
      sleep(0.01)

      # `last_synced_at` is not in CALENDAR_DERIVATION_FIELDS.
      ch.update!(last_synced_at: Time.current)
      expect(ce.reload.updated_at).to be_within(1.second).of(original_updated_at)
    end

    it "cascades the calendar entry on Channel.destroy" do
      ch = create(:channel)
      expect { ch.destroy }.to change(CalendarEntry, :count).by(-1)
    end
  end
end
