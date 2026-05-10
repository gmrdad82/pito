require "rails_helper"

RSpec.describe Video, type: :model, calendar_derivation: true do
  let(:channel) { create(:channel) }

  describe "video → calendar_entry derivation" do
    it "writes a video_published entry when a video flips public" do
      v = create(:video, channel: channel)
      expect {
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
      }.to change(CalendarEntry, :count).by_at_least(1)
      ce = CalendarEntry.where(video_id: v.id, entry_type: :video_published).first
      expect(ce).to be_present
    end

    it "writes a video_scheduled entry when publish_at is set while private" do
      v = create(:video, channel: channel)
      v.update!(privacy_status: :private, publish_at: 5.days.from_now, title: "x", category_id: "10")
      ce = CalendarEntry.where(video_id: v.id, entry_type: :video_scheduled).first
      expect(ce).to be_present
    end

    it "supersedes the prior video_published entry when public → private" do
      v = create(:video, channel: channel)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
      ce = CalendarEntry.where(video_id: v.id, entry_type: :video_published).first
      expect(ce).to be_present

      v.update!(privacy_status: :private)
      expect(ce.reload.state).to eq("superseded")
    end

    it "does NOT re-derive on irrelevant attribute changes" do
      v = create(:video, channel: channel)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
      ce = CalendarEntry.where(video_id: v.id, entry_type: :video_published).first
      original_updated_at = ce.updated_at
      sleep(0.01)

      # `etag` is not in CALENDAR_DERIVATION_FIELDS.
      v.update!(etag: "abc")
      expect(ce.reload.updated_at).to be_within(1.second).of(original_updated_at)
    end

    it "cascades the calendar entry on Video.destroy" do
      v = create(:video, channel: channel)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
      expect { v.destroy }.to change(CalendarEntry, :count).by(-1)
    end
  end
end
