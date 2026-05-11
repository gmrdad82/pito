require "rails_helper"

# Phase 7.5 §11d — Channel preview endpoint request spec.
#
# The endpoint is a pure render surface — no DB writes. The
# `[preview]` button on the channel edit form opens a wide modal
# carrying the initial `ChannelPreviewComponent`; while the modal
# is open, the form's debounced 300ms input listener issues
# `GET /channels/:id/preview?...` and the Turbo-Stream response
# replaces `#channel-preview` inside the modal with a freshly-
# rendered component reflecting the pending edits.
RSpec.describe "Channels::Previews", type: :request do
  let(:channel) do
    create(:channel,
           title: "Cached Title",
           description: "Cached description.",
           subscriber_count: 50)
  end

  describe "GET /channels/:channel_id/preview" do
    it "returns 200 with no pending edits" do
      get channel_preview_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "renders the component with the cached attributes" do
      get channel_preview_path(channel)
      expect(response.body).to include("Cached Title")
      expect(response.body).to include("Cached description.")
    end

    it "honors pending edits in the query string" do
      get channel_preview_path(channel, title: "Streamed Title",
                                        description: "Streamed body.")
      expect(response.body).to include("Streamed Title")
      expect(response.body).to include("Streamed body.")
      expect(response.body).not_to include("Cached Title")
    end

    it "ignores unknown pending params (defense in depth)" do
      get channel_preview_path(channel, title: "Edited", malicious_param: "<script>alert(1)</script>")
      expect(response.body).to include("Edited")
      # The malicious value never reaches an attribute slot.
      expect(response.body).not_to include("<script>alert(1)</script>")
    end

    it "honors active_layout query param" do
      get channel_preview_path(channel, active_layout: "tv")
      expect(response.body).to include("data-active-layout=\"tv\"")
      expect(response.body).to include("preview-layout--tv active")
    end

    it "falls back to desktop when active_layout is unknown" do
      get channel_preview_path(channel, active_layout: "console")
      expect(response.body).to include("data-active-layout=\"desktop\"")
    end

    context "Turbo Stream branch" do
      it "returns text/vnd.turbo-stream.html when Accept is set" do
        get channel_preview_path(channel),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to start_with("text/vnd.turbo-stream.html")
      end

      it "wraps the rendered component in a turbo-stream replace targeting #channel-preview" do
        get channel_preview_path(channel),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("action=\"replace\"")
        expect(response.body).to include("target=\"channel-preview\"")
      end

      it "carries pending edits into the streamed component" do
        get channel_preview_path(channel, title: "Streamed via Turbo"),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include("Streamed via Turbo")
      end
    end

    context "missing channel" do
      it "returns 404 for an unknown id" do
        get "/channels/0/preview"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "links_attributes flattening" do
      it "shapes nested attributes from the edit form into a links array" do
        get channel_preview_path(channel,
                                 links_attributes: {
                                   "0" => { "title" => "stream", "url" => "https://stream.test/", "_destroy" => "no" },
                                   "1" => { "title" => "",       "url" => "https://blank.test/",  "_destroy" => "no" }
                                 })

        # The "stream" entry shows; the blank-title entry is silently dropped.
        expect(response.body).to include(">stream<")
        expect(response.body).to include("https://stream.test/")
        expect(response.body).not_to include("blank.test")
      end

      it "drops entries flagged for destruction" do
        get channel_preview_path(channel,
                                 links_attributes: {
                                   "0" => { "title" => "alive", "url" => "https://alive.test/", "_destroy" => "no" },
                                   "1" => { "title" => "dead",  "url" => "https://dead.test/",  "_destroy" => "yes" }
                                 })

        expect(response.body).to include("https://alive.test/")
        expect(response.body).not_to include("dead.test")
      end
    end
  end
end
