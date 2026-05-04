require "rails_helper"

# Use a stub controller to test the Confirmable concern in isolation.
RSpec.describe Confirmable, type: :request do
  describe "type→model dispatch via DeletionsController" do
    it "loads channel scope when type=channel" do
      channel = create(:channel)
      get deletions_path(type: "channel", ids: channel.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads video scope when type=video" do
      video = create(:video)
      get deletions_path(type: "video", ids: video.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads project scope when type=project" do
      project = create(:project)
      get deletions_path(type: "project", ids: project.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads collection scope when type=collection" do
      collection = create(:collection)
      get deletions_path(type: "collection", ids: collection.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads game scope when type=game" do
      game = create(:game)
      get deletions_path(type: "game", ids: game.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads note scope when type=note" do
      note = create(:note)
      get deletions_path(type: "note", ids: note.id)
      expect(response).to have_http_status(:ok)
    end

    it "loads timeline scope when type=timeline" do
      timeline = create(:timeline)
      get deletions_path(type: "timeline", ids: timeline.id)
      expect(response).to have_http_status(:ok)
    end

    it "redirects to root for unknown type" do
      get deletions_path(type: "playlist", ids: "1")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "via SyncsController" do
    it "loads channel scope when type=channel" do
      channel = create(:channel)
      get syncs_path(type: "channel", ids: channel.id)
      expect(response).to have_http_status(:ok)
    end

    it "redirects to channels index when ids resolve to nothing" do
      get syncs_path(type: "channel", ids: "99999")
      expect(response).to redirect_to(channels_path)
    end

    it "redirects to root for unknown type" do
      get syncs_path(type: "playlist", ids: "1")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "cancel_path / index path dispatch" do
    it "uses channels_path for channel type on empty result" do
      get deletions_path(type: "channel", ids: "99999")
      expect(response).to redirect_to(channels_path)
    end

    it "uses videos_path for video type on empty result" do
      get deletions_path(type: "video", ids: "99999")
      expect(response).to redirect_to(videos_path)
    end

    it "uses projects_path for project type on empty result" do
      get deletions_path(type: "project", ids: "99999")
      expect(response).to redirect_to(projects_path)
    end

    it "uses collections_path for collection type on empty result" do
      get deletions_path(type: "collection", ids: "99999")
      expect(response).to redirect_to(collections_path)
    end

    it "uses games_path for game type on empty result" do
      get deletions_path(type: "game", ids: "99999")
      expect(response).to redirect_to(games_path)
    end

    it "uses projects_path for note type on empty result" do
      get deletions_path(type: "note", ids: "99999")
      expect(response).to redirect_to(projects_path)
    end

    it "uses projects_path for timeline type on empty result" do
      get deletions_path(type: "timeline", ids: "99999")
      expect(response).to redirect_to(projects_path)
    end
  end

  describe "ids parsing" do
    it "splits comma-separated ids" do
      c1 = create(:channel)
      c2 = create(:channel)
      get deletions_path(type: "channel", ids: "#{c1.id},#{c2.id}")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("delete 2 channels")
    end

    it "ignores blank ids" do
      c1 = create(:channel)
      get deletions_path(type: "channel", ids: "#{c1.id},,")
      expect(response).to have_http_status(:ok)
    end
  end
end
