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

    it "is idempotent on re-sync — substantive attrs unchanged" do
      ch = create(:channel)
      ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      original_attrs = ce.attributes.except("updated_at")
      ch.touch
      ch.update!(last_synced_at: Time.current)
      ce.reload
      # `updated_at` shifts on the upsert (the service writes through
      # the scoped `bypass_readonly_for` allowlist + save!); the
      # substantive attributes do not.
      expect(ce.attributes.except("updated_at")).to eq(original_attrs)
    end

    it "Channel.first.touch brings up a channel_published entry on a pre-existing channel" do
      # Simulates the manual playbook step on a seeded channel with no
      # prior derived entry.
      ch = create(:channel)
      CalendarEntry.where(channel_id: ch.id).delete_all
      expect(CalendarEntry.where(channel_id: ch.id).count).to eq(0)
      ch.touch
      expect(CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).count).to eq(1)
    end

    it "cascades the calendar entry on Channel.destroy" do
      ch = create(:channel)
      expect { ch.destroy }.to change(CalendarEntry, :count).by(-1)
    end
  end
end
