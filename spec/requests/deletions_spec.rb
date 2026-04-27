require "rails_helper"

RSpec.describe "Deletions", type: :request do
  describe "GET /deletions (preview)" do
    context "channels" do
      let!(:channel) { create(:channel) }

      it "returns 200 with valid channel IDs" do
        get deletions_path(type: "channel", ids: channel.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(channel.title)
        expect(response.body).to include("delete 1 channel")
      end

      it "shows multiple channels" do
        channel2 = create(:channel)
        get deletions_path(type: "channel", ids: "#{channel.id},#{channel2.id}")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("delete 2 channels")
      end

      it "shows preview table with video count and subscribers" do
        create(:video, channel: channel)
        get deletions_path(type: "channel", ids: channel.id)
        expect(response.body).to include("videos")
        expect(response.body).to include("subscribers")
      end

      it "shows breadcrumb with cancel link" do
        get deletions_path(type: "channel", ids: channel.id)
        expect(response.body).to include("channels")
        expect(response.body).to include("cancel")
      end

      it "shows destructive submit button" do
        get deletions_path(type: "channel", ids: channel.id)
        expect(response.body).to include("btn-danger")
      end

      it "redirects when no items found" do
        get deletions_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end

      it "accepts comma-separated IDs" do
        channel2 = create(:channel)
        get deletions_path(type: "channel", ids: "#{channel.id},#{channel2.id}")
        expect(response).to have_http_status(:ok)
      end

      it "handles dot in IDs gracefully" do
        get deletions_path(type: "channel", ids: channel.id)
        expect(response).to have_http_status(:ok)
      end
    end

    context "videos" do
      let!(:video) { create(:video) }

      it "returns 200 with valid video IDs" do
        get deletions_path(type: "video", ids: video.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(video.title)
        expect(response.body).to include("delete 1 video")
      end

      it "shows channel name in preview" do
        get deletions_path(type: "video", ids: video.id)
        expect(response.body).to include(video.channel.title)
      end
    end

    context "invalid type" do
      it "redirects to root" do
        get deletions_path(type: "invalid", ids: "1")
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /deletions (enqueue)" do
    context "channels" do
      let!(:channel) { create(:channel) }

      it "creates a bulk operation and enqueues job" do
        expect {
          post deletions_path(type: "channel", ids: channel.id)
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkDeleteJob.jobs, :size).by(1)

        operation = BulkOperation.last
        expect(operation.kind).to eq("bulk_delete")
        expect(operation.status).to eq("pending")
        expect(operation.bulk_operation_items.count).to eq(1)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("deleting")
      end

      it "creates items for multiple channels" do
        channel2 = create(:channel)
        post deletions_path(type: "channel", ids: "#{channel.id},#{channel2.id}")
        expect(BulkOperation.last.bulk_operation_items.count).to eq(2)
      end
    end

    context "videos" do
      let!(:video) { create(:video) }

      it "creates a bulk operation for video deletion" do
        expect {
          post deletions_path(type: "video", ids: video.id)
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkDeleteJob.jobs, :size).by(1)
      end
    end

    context "invalid type" do
      it "redirects to root" do
        post deletions_path(type: "invalid", ids: "1")
        expect(response).to redirect_to(root_path)
      end
    end

    context "empty IDs" do
      it "redirects with alert" do
        post deletions_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end
    end
  end
end
