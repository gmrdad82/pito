require "rails_helper"

# Unit A0 — channel read-only conversion.
#
# Asserts the routing contract after the cut: the channel edit / update
# / diff / preview surfaces are gone, their route helpers no longer
# exist, and the surviving read-only routes still resolve.
#
# Idiom note: `recognize_path` raises `ActionController::RoutingError`
# when no route matches a verb. The greedy `/channels/:id` member
# route swallows extra path segments (`/channels/:id/edit` recognizes
# as `id: "<slug>/edit"` or similar) — the real contract is that the
# recognized action is never `edit` / `diff` / `apply_diff` / the
# preview show, and that the named helpers are gone.
RSpec.describe "channel read-only routing", type: :request do
  let!(:channel) { create(:channel) }

  describe "removed route helpers" do
    it "does not expose edit_channel_path" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:edit_channel_path)
    end

    it "does not expose diff_channel_path" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:diff_channel_path)
    end

    it "does not expose apply_diff_channel_path" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:apply_diff_channel_path)
    end

    it "does not expose channel_preview_path" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:channel_preview_path)
    end
  end

  describe "removed routes are not reachable" do
    # `recognize_path` raises `ActionController::RoutingError` when no
    # route matches. The greedy `/channels/:id` member route does NOT
    # span path separators, so `/channels/<slug>/edit` (and `/diff`,
    # `/apply_diff`, `/preview`) match no route at all once the edit /
    # diff / preview routes are gone. The helper below asserts that a
    # path either raises OR — if some other route still claims it —
    # never resolves to the removed action.
    def route_for(path, method)
      Rails.application.routes.recognize_path(path, method: method)
    rescue ActionController::RoutingError
      nil
    end

    it "GET /channels/:id/edit does not route to channels#edit" do
      route = route_for("/channels/#{channel.to_param}/edit", :get)
      expect(route&.dig(:action)).not_to eq("edit")
    end

    it "PATCH /channels/:id (the old general update) is not routable" do
      expect {
        Rails.application.routes.recognize_path(
          "/channels/#{channel.to_param}", method: :patch
        )
      }.to raise_error(ActionController::RoutingError)
    end

    it "GET /channels/:id/diff does not route to channels#diff" do
      route = route_for("/channels/#{channel.to_param}/diff", :get)
      expect(route&.dig(:action)).not_to eq("diff")
    end

    it "PATCH /channels/:id/apply_diff does not route to channels#apply_diff" do
      route = route_for("/channels/#{channel.to_param}/apply_diff", :patch)
      expect(route&.dig(:action)).not_to eq("apply_diff")
    end

    it "GET /channels/:id/preview does not route to a previews controller" do
      route = route_for("/channels/#{channel.to_param}/preview", :get)
      expect(route&.dig(:controller)).not_to eq("channels/previews")
    end
  end

  describe "surviving routes still resolve" do
    it "GET /channels" do
      route = Rails.application.routes.recognize_path("/channels", method: :get)
      expect(route).to include(controller: "channels", action: "index")
    end

    it "GET /channels/:id" do
      route = Rails.application.routes.recognize_path(
        "/channels/#{channel.to_param}", method: :get
      )
      expect(route).to include(controller: "channels", action: "show")
    end

    it "GET /channels/:id/history" do
      route = Rails.application.routes.recognize_path(
        "/channels/#{channel.to_param}/history", method: :get
      )
      expect(route).to include(controller: "channels/change_logs", action: "index")
    end

    it "GET /channels/:id/videos" do
      route = Rails.application.routes.recognize_path(
        "/channels/#{channel.to_param}/videos", method: :get
      )
      expect(route).to include(controller: "channels", action: "videos")
    end

    it "PATCH /channels/:id/star" do
      route = Rails.application.routes.recognize_path(
        "/channels/#{channel.to_param}/star", method: :patch
      )
      expect(route).to include(controller: "channels/stars", action: "update")
    end

    it "GET /channels/:id/revoke" do
      route = Rails.application.routes.recognize_path(
        "/channels/#{channel.to_param}/revoke", method: :get
      )
      expect(route).to include(controller: "channel_revokes", action: "show")
    end
  end
end
