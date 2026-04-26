require "rails_helper"

RSpec.describe "Channels", type: :request do
  describe "GET /channels" do
    it "returns 200" do
      get channels_path
      expect(response).to have_http_status(:ok)
    end

    it "has page title" do
      get channels_path
      expect(response.body).to include("<title>channels ~ pito</title>")
    end

    it "shows empty state when no channels" do
      get channels_path
      expect(response.body).to include("no channels yet")
    end

    it "includes add channel link" do
      get channels_path
      expect(response.body).to include("add channel")
    end

    context "with channels" do
      let!(:channel) { create(:channel, :connected, subscriber_count: 1000, view_count: 50_000) }
      let!(:video) { create(:video, channel: channel) }

      it "displays the channels table" do
        get channels_path
        expect(response.body).to include(channel.title)
        expect(response.body).to include("1,000")
        expect(response.body).to include("50,000")
        expect(response.body).to include("yes")
      end

      it "includes open link per row" do
        get channels_path
        expect(response.body).to include("open")
      end

      it "shows video count" do
        get channels_path
        expect(response.body).to include(">1<")
      end
    end
  end
end
