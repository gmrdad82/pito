require "rails_helper"

RSpec.describe "Analytics dashboard (top-level)", type: :request do
  describe "GET /analytics" do
    context "auth" do
      it "redirects to /login when unauthenticated", :unauthenticated do
        get "/analytics"
        expect(response).to redirect_to(login_path)
      end

      it "renders 200 when authenticated" do
        get "/analytics"
        expect(response).to have_http_status(:ok)
      end
    end

    context "window picker" do
      it "defaults to ?window=28d when no query string is supplied" do
        get "/analytics"
        expect(response.body).to include('data-analytics-window-picker-current-value="28d"')
      end

      %w[7d 28d 90d lifetime].each do |window|
        it "renders the chosen window when ?window=#{window}" do
          get "/analytics", params: { window: window }
          expect(response.body).to include(%(data-analytics-window-picker-current-value="#{window}"))
        end
      end

      it "falls back to the default for an unknown window value" do
        get "/analytics", params: { window: "14d" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-analytics-window-picker-current-value="28d"')
      end
    end

    context "cross-channel summary" do
      let(:connection_a) { create(:youtube_connection) }
      let(:connection_b) { create(:youtube_connection) }
      let(:channel_a)    { create(:channel, youtube_connection: connection_a) }
      let(:channel_b)    { create(:channel, youtube_connection: connection_b) }

      it "renders cross-channel summary cards summing across connected channels" do
        create(:channel_window_summary, channel: channel_a, window: "28d",
                                        views: 100, estimated_minutes_watched: 50,
                                        subscribers_gained: 10, subscribers_lost: 2, likes: 25)
        create(:channel_window_summary, channel: channel_b, window: "28d",
                                        views: 200, estimated_minutes_watched: 80,
                                        subscribers_gained: 5, subscribers_lost: 1, likes: 10)

        get "/analytics"
        expect(response.body).to include("cross-channel summary")
        expect(response.body).to include("300") # views sum
        expect(response.body).to include("130") # watch time sum
      end

      it "renders zero values when no analytics rows exist" do
        channel_a
        channel_b
        get "/analytics"
        expect(response.body).to include("cross-channel summary")
        expect(response.body).to include(">0<").or include("0\n")
      end
    end

    context "channel cards" do
      it "renders one card per channel" do
        connection_a = create(:youtube_connection)
        connection_b = create(:youtube_connection)
        create(:channel, youtube_connection: connection_a)
        create(:channel, youtube_connection: connection_b)

        get "/analytics"
        expect(response.body.scan(/class="analytics-channel-card"/).size).to eq(2)
      end

      # Post-cleanup — every channel is OAuth-linked by definition,
      # so analytics renders a card for every channel regardless of
      # `youtube_connection_id`. Channels with no analytics rows for
      # the chosen window collapse to the "no data" caption.
      it "renders cards for channels even when youtube_connection_id is nil" do
        connection = create(:youtube_connection)
        create(:channel, youtube_connection: connection)
        create(:channel, youtube_connection: nil)

        get "/analytics"
        expect(response.body.scan(/class="analytics-channel-card"/).size).to eq(2)
      end
    end

    context "cross-video local rollups" do
      it "renders the four rollup chart sections" do
        get "/analytics"
        expect(response.body).to include("when to publish")
        expect(response.body).to include("best video length")
        expect(response.body).to include("topics that work")
        expect(response.body).to include("thumbnail decay")
      end
    end

    context "data freshness" do
      it "renders 'never synced' when no audit rows exist" do
        get "/analytics"
        expect(response.body).to include("never synced")
      end

      it "renders 'synced ... ago' when audit rows exist" do
        connection = create(:youtube_connection)
        create(:youtube_api_call,
               youtube_connection: connection,
               client_kind: "analytics_v2",
               outcome: "succeeded",
               endpoint: "reports.query",
               http_method: "GET",
               units: 0)
        get "/analytics"
        expect(response.body).to match(/synced .+ ago/)
      end
    end
  end
end
