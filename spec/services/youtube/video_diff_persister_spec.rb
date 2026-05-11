require "rails_helper"

RSpec.describe Youtube::VideoDiffPersister do
  let(:video) { create(:video) }

  describe ".call" do
    context "with an empty diff" do
      it "stamps last_diff_checked_at and returns nil" do
        result = described_class.call(video: video, diff_hash: {})
        expect(result).to be_nil
        expect(video.reload.last_diff_checked_at).to be_within(2.seconds).of(Time.current)
      end

      it "does not insert a VideoDiff row" do
        expect {
          described_class.call(video: video, diff_hash: {})
        }.not_to change(VideoDiff, :count)
      end
    end

    context "with a non-empty diff and no existing open diff" do
      let(:diff_hash) do
        { "title" => { "pito" => "p", "youtube" => "y" } }
      end

      it "creates a VideoDiff row with the payload" do
        diff = described_class.call(video: video, diff_hash: diff_hash)
        expect(diff).to be_present
        expect(diff.payload).to eq(diff_hash)
        expect(diff.video).to eq(video)
        expect(diff.resolved_at).to be_nil
      end

      it "stamps last_diff_checked_at" do
        described_class.call(video: video, diff_hash: diff_hash)
        expect(video.reload.last_diff_checked_at).to be_within(2.seconds).of(Time.current)
      end
    end

    context "with an existing open diff" do
      let!(:existing) do
        create(:video_diff, video: video, payload: { "title" => { "pito" => "old_p", "youtube" => "old_y" } })
      end
      let(:new_diff_hash) do
        { "description" => { "pito" => "p", "youtube" => "y" } }
      end

      it "updates the existing row's payload" do
        result = described_class.call(video: video, diff_hash: new_diff_hash)
        expect(result.id).to eq(existing.id)
        expect(result.payload).to eq(new_diff_hash)
      end

      it "leaves resolved_at nil" do
        result = described_class.call(video: video, diff_hash: new_diff_hash)
        expect(result.resolved_at).to be_nil
      end

      it "does not create a second row" do
        expect {
          described_class.call(video: video, diff_hash: new_diff_hash)
        }.not_to change(VideoDiff, :count)
      end
    end

    context "with a resolved diff in history" do
      let!(:resolved) { create(:video_diff, :resolved, video: video) }
      let(:diff_hash) do
        { "title" => { "pito" => "p2", "youtube" => "y2" } }
      end

      it "creates a new open row (preserves the resolved row)" do
        result = described_class.call(video: video, diff_hash: diff_hash)
        expect(result.id).not_to eq(resolved.id)
        expect(VideoDiff.where(video: video).count).to eq(2)
      end
    end
  end
end
