require "rails_helper"

RSpec.describe "SavedViews", type: :request do
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
