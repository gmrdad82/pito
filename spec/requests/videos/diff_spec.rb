require "rails_helper"

RSpec.describe "Videos diff", type: :request do
  let(:user) { create(:user) }
  let(:youtube_connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: youtube_connection)
  end
  let(:video) { create(:video, channel: channel, title: "local title") }

  describe "GET /videos/:slug/diff" do
    context "with an open diff" do
      let!(:diff) do
        create(:video_diff, video: video, payload: {
          "title" => { "pito" => "local title", "youtube" => "remote title" }
        })
      end

      it "renders the diff page with 200" do
        get diff_video_path(video)
        expect(response).to have_http_status(:ok)
      end

      it "shows both column values in the response body" do
        get diff_video_path(video)
        expect(response.body).to include("local title")
        expect(response.body).to include("remote title")
      end

      it "renders the radio group with accept youtube as the default" do
        get diff_video_path(video)
        expect(response.body).to include("decisions[title]")
        # Find the youtube radio for the title row and verify it's checked.
        expect(response.body).to match(
          %r{<input[^>]*name="decisions\[title\]"[^>]*value="youtube"[^>]*checked}
        )
      end

      it "returns JSON parity on the .json branch" do
        get diff_video_path(video, format: :json)
        json = JSON.parse(response.body)
        expect(json["diff_id"]).to eq(diff.id)
        expect(json["fields"]).to eq([ "title" ])
        expect(json["writable_fields"]).to include("title")
      end
    end

    context "with no open diff" do
      it "redirects to the video show with a flash notice" do
        get diff_video_path(video)
        expect(response).to redirect_to(video_path(video))
        follow_redirect!
        expect(response.body).to include("no open diff")
      end

      it "JSON branch returns 404 with a clear error envelope" do
        get diff_video_path(video, format: :json)
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)).to eq("error" => "no_open_diff")
      end
    end

    context "with a stale slug" do
      let!(:diff) do
        create(:video_diff, video: video, payload: {
          "title" => { "pito" => "p", "youtube" => "y" }
        })
      end

      it "301-redirects to the canonical slug when called by integer id" do
        get diff_video_path(id: video.id)
        expect(response).to have_http_status(:moved_permanently)
        expect(response.location).to end_with(diff_video_path(video))
      end
    end
  end

  describe "PATCH /videos/:slug/apply_diff" do
    let!(:diff) do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      })
    end

    context "happy: youtube-wins applied" do
      it "updates the local column and redirects" do
        patch apply_diff_video_path(video), params: { decisions: { "title" => "youtube" } }
        expect(response).to redirect_to(video_path(video))
        follow_redirect!
        expect(response.body).to include("diff resolved")
        video.reload
        expect(video.title).to eq("remote title")
      end

      it "marks the VideoDiff resolved" do
        patch apply_diff_video_path(video), params: { decisions: { "title" => "youtube" } }
        diff.reload
        expect(diff.resolved_at).to be_present
      end

      it "appends a VideoChangeLog row" do
        expect {
          patch apply_diff_video_path(video), params: { decisions: { "title" => "youtube" } }
        }.to change(VideoChangeLog, :count).by(1)
      end

      it "JSON branch returns ok: true" do
        patch apply_diff_video_path(video, format: :json),
              params: { decisions: { "title" => "youtube" } }.to_json,
              headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["ok"]).to be(true)
      end
    end

    context "flaw: no decisions submitted" do
      it "re-renders the diff page with an error" do
        patch apply_diff_video_path(video), params: { decisions: {} }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("no decision")
      end
    end

    context "flaw: stale diff (decision references a field not in payload)" do
      it "re-renders with stale_diff error" do
        patch apply_diff_video_path(video), params: { decisions: { "title" => "pito", "garbage" => "pito" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("not in diff").or include("stale")
      end
    end

    context "flaw: already-resolved (idempotency)" do
      before do
        diff.update!(resolved_at: 1.minute.ago, resolution_payload: { "title" => "youtube" })
      end

      it "redirects to the video show because no open diff exists" do
        patch apply_diff_video_path(video), params: { decisions: { "title" => "youtube" } }
        expect(response).to redirect_to(video_path(video))
        follow_redirect!
        expect(response.body).to include("no open diff")
      end
    end
  end

  describe "GET /videos/diffs (paginated index)" do
    it "returns 200 with empty state when no diffs are open" do
      get diffs_videos_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no open diffs")
    end

    it "lists open diffs with a [view diff] link" do
      create(:video_diff, video: video, payload: {
        "title" => { "pito" => "p", "youtube" => "y" }
      })
      get diffs_videos_path
      expect(response.body).to include(video.title)
      expect(response.body).to include("[ view diff ]")
    end

    it "returns JSON parity on the .json branch" do
      diff = create(:video_diff, video: video, payload: {
        "title" => { "pito" => "p", "youtube" => "y" }
      })
      get diffs_videos_path(format: :json)
      json = JSON.parse(response.body)
      expect(json["total_count"]).to eq(1)
      expect(json["diffs"].first["diff_id"]).to eq(diff.id)
    end
  end
end
