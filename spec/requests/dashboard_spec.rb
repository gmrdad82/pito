require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /" do
    it "returns 200" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "shows empty state when no videos" do
      get root_path
      expect(response.body).to include("no videos yet")
    end

    context "with data" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }

      it "shows summary counts" do
        get root_path
        expect(response.body).to include("1 videos across 1 channels")
      end

      it "has the default page title" do
        get root_path
        expect(response.body).to include("<title>pito ~ best YouTube tool</title>")
      end
    end
  end
end
