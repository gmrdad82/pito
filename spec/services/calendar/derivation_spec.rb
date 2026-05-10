require "rails_helper"

RSpec.describe Calendar::Derivation do
  describe ".sync!" do
    let(:channel) { create(:channel) }

    context "Video host" do
      let(:video) { create(:video, channel: channel) }

      it "writes a new video_published entry on first sync of a public video" do
        video.update!(privacy_status: :public, published_at: 1.day.ago, title: "hello", category_id: "10")
        # The after_save_commit hook already wrote the entry.
        ce = CalendarEntry.where(entry_type: :video_published).where(video_id: video.id).first
        expect(ce).to be_present
        expect(ce.title).to eq("video published: hello")
        expect(ce.starts_at).to be_within(1.second).of(video.published_at)
      end

      it "is idempotent on second sync with same state" do
        video.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
        expect {
          described_class.sync!(video)
        }.not_to change(CalendarEntry, :count)
      end

      it "overwrites the title on a subsequent title change" do
        video.update!(privacy_status: :public, published_at: 1.day.ago, title: "old", category_id: "10")
        ce = CalendarEntry.where(video_id: video.id, entry_type: :video_published).first
        expect(ce.title).to eq("video published: old")
        video.update!(title: "new")
        expect(ce.reload.title).to eq("video published: new")
      end

      it "preserves metadata.user_overrides on overwrite" do
        video.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
        ce = CalendarEntry.where(video_id: video.id, entry_type: :video_published).first
        ce.bypass_readonly = true
        meta = ce.metadata.deep_dup
        meta["user_overrides"] = { "note" => "manually added" }
        ce.update!(metadata: meta)

        video.update!(title: "renamed")
        expect(ce.reload.metadata["user_overrides"]).to eq("note" => "manually added")
      end

      it "writes video_scheduled when the video is private and publish_at is future" do
        video.update!(privacy_status: :private, publish_at: 5.days.from_now, title: "p", category_id: "10")
        ce = CalendarEntry.where(video_id: video.id, entry_type: :video_scheduled).first
        expect(ce).to be_present
      end

      it "transitions scheduled → published by writing a fresh published entry and superseding the scheduled one" do
        video.update!(privacy_status: :private, publish_at: 5.days.from_now, title: "p", category_id: "10")
        scheduled_ce = CalendarEntry.where(video_id: video.id, entry_type: :video_scheduled).first
        expect(scheduled_ce.state).to eq("scheduled")

        # Flip to public.
        video.update!(privacy_status: :public, publish_at: nil, published_at: Time.current)
        # The hook revokes the scheduled entry (it's no longer the
        # current derivation) and writes a new published entry.
        expect(CalendarEntry.where(video_id: video.id, entry_type: :video_published).count).to eq(1)
      end
    end

    context "Channel host" do
      it "writes channel_published keyed on created_at" do
        ch = create(:channel)
        ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
        expect(ce).to be_present
        expect(ce.starts_at).to be_within(1.second).of(ch.created_at)
        expect(ce.all_day).to be(true)
      end
    end

    context "Game host" do
      let(:phase_14_ready?) { Game.column_names.include?("release_date") }

      it "is a no-op on Game with release_date=nil" do
        skip "Phase 14 release_date column not present" unless phase_14_ready?

        g = create(:game)
        # No release_date set → no entry derived.
        expect(CalendarEntry.where(game_id: g.id).count).to eq(0)
      end

      it "writes game_release when release_date is set" do
        skip "Phase 14 release_date column not present" unless phase_14_ready?

        g = create(:game)
        g.update!(release_date: 30.days.from_now)
        ce = CalendarEntry.where(game_id: g.id, entry_type: :game_release).first
        expect(ce).to be_present
        expect(ce.title).to start_with("released: ")
      end
    end
  end

  describe ".revoke!" do
    it "flips state to superseded, does NOT delete" do
      video = create(:video)
      video.update!(privacy_status: :public, published_at: 1.day.ago, title: "x", category_id: "10")
      ce = CalendarEntry.where(video_id: video.id, entry_type: :video_published).first
      expect(ce).to be_present

      described_class.revoke!(video)
      expect(ce.reload.state).to eq("superseded")
      expect(CalendarEntry.where(id: ce.id).exists?).to be(true)
    end
  end
end
