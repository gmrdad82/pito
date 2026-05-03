require "rails_helper"

RSpec.describe "SavedViews", type: :request do
  describe "GET /saved_views.json" do
    let!(:channel_view) do
      create(:saved_view, kind: :channels, name: "starred", url: "/channels?star=yes", position: 0)
    end
    let!(:video_view) do
      create(:saved_view, kind: :videos, name: "recent", url: "/videos", position: 1)
    end

    it "returns 200 with all saved views as a JSON array" do
      get saved_views_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.size).to eq(2)
    end

    it "returns the SavedView shape pito-sh expects" do
      get saved_views_path(format: :json)
      json = response.parsed_body
      row = json.first
      expect(row.keys).to match_array(%w[id kind name url])
      expect(row["kind"]).to be_a(String)
      expect(row["name"]).to be_a(String)
      expect(row["url"]).to be_a(String)
      expect(row["id"]).to be_a(Integer)
    end

    it "respects the `ordered` scope (position asc, created_at desc)" do
      get saved_views_path(format: :json)
      json = response.parsed_body
      expect(json.map { |v| v["id"] }).to eq([ channel_view.id, video_view.id ])
    end

    it "is reachable without an authentication token" do
      get saved_views_path(format: :json)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /saved_views" do
    it "creates a saved view and redirects to its URL" do
      expect {
        post saved_views_path, params: { saved_view: { kind: "channels", url: "/channels/panes?ids=1,2", name: "my view" } }
      }.to change(SavedView, :count).by(1)

      expect(response).to redirect_to("/channels/panes?ids=1,2")
      follow_redirect!
      expect(response.body).to include("view saved.")
    end

    it "assigns auto-incrementing position" do
      create(:saved_view, kind: :channels, position: 2)
      post saved_views_path, params: { saved_view: { kind: "channels", url: "/channels/1", name: "second" } }
      expect(SavedView.last.position).to eq(3)
    end

    it "handles duplicate URL gracefully" do
      existing = create(:saved_view, kind: :channels, url: "/channels/1", name: "existing")
      post saved_views_path, params: { saved_view: { kind: "channels", url: "/channels/1", name: "duplicate" } }
      expect(response).to redirect_to("/channels/1")
      expect(SavedView.count).to eq(1)
    end

    it "redirects back with alert on invalid params" do
      post saved_views_path, params: { saved_view: { kind: "channels", url: "", name: "" } },
           headers: { "HTTP_REFERER" => "/channels" }
      expect(response).to redirect_to("/channels")
    end

    it "starts position at 0 when no existing views" do
      post saved_views_path, params: { saved_view: { kind: "channels", url: "/channels/1", name: "first" } }
      expect(SavedView.last.position).to eq(0)
    end
  end

  describe "DELETE /saved_views/:id" do
    it "deletes a channel saved view and redirects to channels" do
      view = create(:saved_view, kind: :channels)
      expect {
        delete saved_view_path(view)
      }.to change(SavedView, :count).by(-1)

      expect(response).to redirect_to(channels_path)
    end

    it "deletes a video saved view and redirects to videos" do
      view = create(:saved_view, kind: :videos)
      delete saved_view_path(view)
      expect(response).to redirect_to(videos_path)
    end
  end
end
