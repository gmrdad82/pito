require "rails_helper"

RSpec.describe Youtube::VideoDiffApply do
  let(:user) { create(:user) }
  let(:youtube_connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: youtube_connection)
  end
  let(:video) do
    create(:video, channel: channel, title: "local title",
                   description: "local body")
  end

  let(:fresh_snapshot) do
    {
      snippet: { title: "remote title", description: "remote body" },
      status:  { privacyStatus: "private" }
    }
  end

  let(:reader_double) do
    instance_double(Youtube::VideosReader, read_video: fresh_snapshot)
  end
  let(:client_double) do
    instance_double(Youtube::VideosClient, update_video: { id: video.youtube_video_id })
  end

  describe "validation" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      })
    end

    it "rejects missing decisions" do
      result = described_class.call(video_diff: diff, decisions: {}, user: user,
                                    reader: reader_double, client: client_double)
      expect(result.success?).to be(false)
      expect(result.error_code).to eq("missing_decisions")
    end

    it "rejects an invalid decision value" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "bogus" },
        user: user, reader: reader_double, client: client_double
      )
      expect(result.success?).to be(false)
      expect(result.error_code).to eq("invalid_decision")
    end

    it "rejects decisions on fields not in the diff payload" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito", "garbage" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
      expect(result.success?).to be(false)
      expect(result.error_code).to eq("stale_diff")
    end

    it "rejects when the diff is already resolved" do
      diff.update!(resolved_at: 1.day.ago, resolution_payload: { "title" => "youtube" })
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
      expect(result.success?).to be(false)
      expect(result.error_code).to eq("already_resolved")
    end
  end

  describe "youtube-wins decisions" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title"       => { "pito" => "local title", "youtube" => "remote title" },
        "description" => { "pito" => "local body",  "youtube" => "remote body" }
      })
    end

    it "writes the YouTube value to the local Pito columns" do
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "youtube", "description" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )

      video.reload
      expect(video.title).to eq("remote title")
      expect(video.description).to eq("remote body")
    end

    it "logs a youtube_pull row for each field" do
      expect {
        described_class.call(
          video_diff: diff,
          decisions: { "title" => "youtube", "description" => "youtube" },
          user: user, reader: reader_double, client: client_double
        )
      }.to change(VideoChangeLog, :count).by(2)

      log = VideoChangeLog.last
      expect(log.source).to eq("youtube_pull")
      expect(log.changed_by_user_id).to eq(user.id)
    end

    it "marks the diff resolved with resolution_payload" do
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "youtube", "description" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )

      diff.reload
      expect(diff.resolved_at).to be_present
      expect(diff.resolved_by_user_id).to eq(user.id)
      expect(diff.resolution_payload).to eq({ "title" => "youtube", "description" => "youtube" })
    end

    it "does NOT call the YouTube client for YouTube-wins only" do
      expect(client_double).not_to receive(:update_video)
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "youtube", "description" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )
    end
  end

  describe "pito-wins decisions" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      })
    end

    it "calls the YouTube client with the pito-wins fields" do
      expect(client_double).to receive(:update_video).with(
        video, fresh: fresh_snapshot, fields: [ :title ]
      )
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
    end

    it "leaves the local title untouched (already the pito value)" do
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
      expect(video.reload.title).to eq("local title")
    end

    it "stamps title_changed_at when title is pito-wins (Q1 audit)" do
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
      expect(video.reload.title_changed_at).to be_present
    end

    it "logs a pito_apply row" do
      expect {
        described_class.call(
          video_diff: diff,
          decisions: { "title" => "pito" },
          user: user, reader: reader_double, client: client_double
        )
      }.to change(VideoChangeLog, :count).by(1)

      log = VideoChangeLog.last
      expect(log.source).to eq("pito_apply")
      expect(log.field).to eq("title")
      expect(log.new_value).to eq("local title")
      expect(log.old_value).to eq("remote title")
    end
  end

  describe "mixed decisions" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title"       => { "pito" => "local title", "youtube" => "remote title" },
        "description" => { "pito" => "local body",  "youtube" => "remote body" }
      })
    end

    it "pushes Pito-wins to YouTube + pulls YouTube-wins to Pito" do
      expect(client_double).to receive(:update_video).with(
        video, fresh: fresh_snapshot, fields: [ :title ]
      )

      described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito", "description" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )

      video.reload
      expect(video.title).to eq("local title")
      expect(video.description).to eq("remote body")
    end

    it "creates a VideoChangeLog row for each applied field" do
      expect {
        described_class.call(
          video_diff: diff,
          decisions: { "title" => "pito", "description" => "youtube" },
          user: user, reader: reader_double, client: client_double
        )
      }.to change(VideoChangeLog, :count).by(2)

      logs = VideoChangeLog.where(video: video)
      expect(logs.where(field: "title").first.source).to eq("pito_apply")
      expect(logs.where(field: "description").first.source).to eq("youtube_pull")
    end
  end

  describe "display-only field cannot be pito-wins" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "view_count" => { "pito" => 100, "youtube" => 200 }
      })
    end

    it "rejects accept-pito on view_count with a validation error" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "view_count" => "pito" },
        user: user, reader: reader_double, client: client_double
      )

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("validation_error")
    end

    it "accepts youtube-wins on view_count" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "view_count" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )

      expect(result.success?).to be(true)
      expect(video.reload.view_count).to eq(200)
    end
  end

  describe "YouTube push failure" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      })
    end

    before do
      allow(client_double).to receive(:update_video)
        .and_raise(Youtube::ValidationError.new("invalid title"))
    end

    it "returns a validation result and rolls back local writes" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("youtube_validation")
    end

    it "does NOT mark the diff resolved on push failure" do
      described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )

      diff.reload
      expect(diff.resolved_at).to be_nil
    end

    it "does NOT append a VideoChangeLog row when the push fails" do
      expect {
        described_class.call(
          video_diff: diff,
          decisions: { "title" => "pito" },
          user: user, reader: reader_double, client: client_double
        )
      }.not_to change(VideoChangeLog, :count)
    end
  end

  describe "no youtube connection on channel" do
    let(:lonely_channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuw",
             youtube_connection: nil)
    end
    let(:lonely_video) { create(:video, channel: lonely_channel) }
    let(:diff) do
      create(:video_diff, video: lonely_video, payload: {
        "title" => { "pito" => "local", "youtube" => "remote" }
      })
    end

    it "rejects pito-wins with no connection" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )

      expect(result.success?).to be(false)
      expect(result.error_code).to eq("validation_error")
    end

    it "accepts youtube-wins with no connection (no push needed)" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "youtube" },
        user: user, reader: reader_double, client: client_double
      )

      expect(result.success?).to be(true)
    end
  end

  describe "quota-exhausted upstream" do
    let(:diff) do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "p", "youtube" => "y" }
      })
    end

    before do
      allow(client_double).to receive(:update_video)
        .and_raise(Youtube::QuotaExhaustedError.new("daily quota"))
    end

    it "returns a quota_exhausted result" do
      result = described_class.call(
        video_diff: diff,
        decisions: { "title" => "pito" },
        user: user, reader: reader_double, client: client_double
      )
      expect(result.success?).to be(false)
      expect(result.error_code).to eq("quota_exhausted")
    end
  end
end
