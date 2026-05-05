require "rails_helper"

RSpec.describe "Deletions", type: :request do
  describe "GET /deletions (preview)" do
    context "channels" do
      let!(:channel) { create(:channel) }

      it "returns 200 with valid channel IDs" do
        get deletions_path(type: "channel", ids: channel.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("delete 1 channel")
      end

      it "shows multiple channels" do
        channel2 = create(:channel)
        get deletions_path(type: "channel", ids: "#{channel.id},#{channel2.id}")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("delete 2 channels")
      end

      it "shows preview table with video count and url" do
        create(:video, channel: channel)
        get deletions_path(type: "channel", ids: channel.id)
        expect(response.body).to include("videos")
        expect(response.body).to include("<th>URL</th>")
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

      it "handles single ID gracefully" do
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

      it "shows channel url in preview" do
        get deletions_path(type: "video", ids: video.id)
        expect(response.body).to include(video.channel.channel_url)
      end
    end

    context "projects" do
      let!(:project) { create(:project, name: "Demo project") }

      it "returns 200 with valid project IDs and renders the preview" do
        get deletions_path(type: "project", ids: project.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Demo project")
        expect(response.body).to include("delete 1 project")
      end

      it "shows the cancel breadcrumb back to projects index" do
        get deletions_path(type: "project", ids: project.id)
        expect(response.body).to include("projects")
      end

      it "redirects to projects index when no items found" do
        get deletions_path(type: "project", ids: "99999")
        expect(response).to redirect_to(projects_path)
      end
    end

    context "collections" do
      let!(:collection) { create(:collection, name: "Action games") }

      it "returns 200 with valid collection IDs and renders the preview" do
        get deletions_path(type: "collection", ids: collection.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Action games")
        expect(response.body).to include("delete 1 collection")
      end
    end

    context "games" do
      let!(:game) { create(:game, title: "Elden Ring") }

      it "returns 200 with valid game IDs and renders the preview" do
        get deletions_path(type: "game", ids: game.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Elden Ring")
        expect(response.body).to include("delete 1 game")
      end
    end

    context "notes" do
      let!(:note) { create(:note, title: "intro draft") }

      it "returns 200 with valid note IDs and renders the preview" do
        get deletions_path(type: "note", ids: note.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("intro draft")
        expect(response.body).to include("delete 1 note")
      end
    end

    context "timelines" do
      let!(:timeline) { create(:timeline, title: "ep01 cut") }

      it "returns 200 with valid timeline IDs and renders the preview" do
        get deletions_path(type: "timeline", ids: timeline.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ep01 cut")
        expect(response.body).to include("delete 1 timeline")
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

    context "projects" do
      let!(:project) { create(:project) }

      it "creates a bulk operation for project deletion" do
        expect {
          post deletions_path(type: "project", ids: project.id)
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkDeleteJob.jobs, :size).by(1)

        operation = BulkOperation.last
        expect(operation.bulk_operation_items.count).to eq(1)
        item = operation.bulk_operation_items.first
        expect(item.target_type).to eq("Project")
        expect(item.target_id).to eq(project.id)
      end

      it "executes BulkDeleteJob and destroys the project" do
        post deletions_path(type: "project", ids: project.id)
        operation = BulkOperation.last

        expect {
          BulkDeleteJob.new.perform(operation.id)
        }.to change(Project, :count).by(-1)

        expect(operation.reload.status).to eq("completed")
      end
    end

    context "collections" do
      let!(:collection) { create(:collection) }

      it "creates a bulk operation and destroys the collection on perform" do
        post deletions_path(type: "collection", ids: collection.id)
        operation = BulkOperation.last

        expect {
          BulkDeleteJob.new.perform(operation.id)
        }.to change(Collection, :count).by(-1)
      end
    end

    context "games" do
      let!(:game) { create(:game) }

      it "creates a bulk operation and destroys the game on perform" do
        post deletions_path(type: "game", ids: game.id)
        operation = BulkOperation.last

        expect {
          BulkDeleteJob.new.perform(operation.id)
        }.to change(Game, :count).by(-1)
      end
    end

    context "notes" do
      let!(:note) { create(:note) }

      it "creates a bulk operation and destroys the note on perform" do
        post deletions_path(type: "note", ids: note.id)
        operation = BulkOperation.last

        expect {
          BulkDeleteJob.new.perform(operation.id)
        }.to change(Note, :count).by(-1)
      end
    end

    context "timelines" do
      let!(:timeline) { create(:timeline) }

      it "creates a bulk operation and destroys the timeline on perform" do
        post deletions_path(type: "timeline", ids: timeline.id)
        operation = BulkOperation.last

        expect {
          BulkDeleteJob.new.perform(operation.id)
        }.to change(Timeline, :count).by(-1)
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

  describe "GET /deletions (preview, JSON)" do
    let!(:channel) { create(:channel) }

    it "returns the BulkOperationResponse preview shape for channels" do
      channel2 = create(:channel)
      get deletions_path(type: "channel", ids: "#{channel.id},#{channel2.id}", format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("preview")
      expect(data["total"]).to eq(2)
      expect(data["syncable"]).to match_array([ channel.id, channel2.id ])
      expect(data["skipped"]).to eq([])
      expect(data["operation_id"]).to be_nil
      expect(data["message"]).to be_a(String)
    end

    it "returns BulkOperationResponse preview for a single video" do
      video = create(:video)
      get deletions_path(type: "video", ids: video.id, format: :json)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("preview")
      expect(data["total"]).to eq(1)
      expect(data["syncable"]).to eq([ video.id ])
      expect(data["skipped"]).to eq([])
      expect(data["operation_id"]).to be_nil
    end

    it "returns 422 JSON for unknown type" do
      get deletions_path(type: "invalid", ids: "1", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error")
    end

    it "returns 422 JSON when no items match" do
      get deletions_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error")
    end
  end

  describe "POST /deletions (enqueue, JSON)" do
    let!(:channel) { create(:channel) }

    it "creates a bulk operation and returns the BulkOperationResponse enqueued shape" do
      expect {
        post deletions_path(type: "channel", ids: channel.id, format: :json)
      }.to change(BulkOperation, :count).by(1)
        .and change(BulkDeleteJob.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq("application/json")

      operation = BulkOperation.last
      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("enqueued")
      expect(data["total"]).to eq(1)
      expect(data["syncable"]).to eq([])
      expect(data["skipped"]).to eq([])
      expect(data["operation_id"]).to eq(operation.id)
      expect(data["status_url"]).to eq(status_bulk_operation_path(operation, format: :json))
      expect(data["message"]).to match(/Bulk delete queued/i)
    end

    it "succeeds without an authenticity token (CSRF skipped for JSON)" do
      ActionController::Base.allow_forgery_protection = true
      begin
        post deletions_path(type: "channel", ids: channel.id, format: :json)
        expect(response).to have_http_status(:accepted)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "returns 422 JSON for unknown type" do
      post deletions_path(type: "invalid", ids: "1", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 JSON when no items match" do
      post deletions_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
