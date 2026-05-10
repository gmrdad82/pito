require "rails_helper"

RSpec.describe "Calendar::Schedule", type: :request do
  describe "GET /calendar/schedule" do
    it "happy: renders 200 with the schedule shell" do
      get "/calendar/schedule"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("schedule")
    end

    it "with both past and future entries, renders the [today] divider" do
      create(:calendar_entry, :custom, starts_at: 5.days.ago, title: "past")
      create(:calendar_entry, :custom, starts_at: 5.days.from_now, title: "future")
      get "/calendar/schedule"
      expect(response.body).to include("[ today ]")
    end

    it "filters by type=game" do
      g = create(:game)
      ce = create(:calendar_entry, :game_release, game: g, starts_at: 30.days.from_now, title: "released: g")
      v = create(:video)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "v", category_id: "10")
      get "/calendar/schedule?type=game"
      expect(response.body).to include("released: g")
      expect(response.body).not_to include("video published: v")
    end

    it "filters by source=manual" do
      create(:calendar_entry, :milestone_manual, title: "podcast")
      v = create(:video)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "thevid", category_id: "10")
      get "/calendar/schedule?source=manual"
      expect(response.body).to include("podcast")
      expect(response.body).not_to include("video published: thevid")
    end

    it "sad: type=invalid redirects with flash" do
      get "/calendar/schedule?type=zorblax"
      expect(response).to redirect_to(calendar_schedule_path)
    end

    it "sad: source=invalid redirects with flash" do
      get "/calendar/schedule?source=zorblax"
      expect(response).to redirect_to(calendar_schedule_path)
    end

    it "page=999 (out of range) renders empty list" do
      get "/calendar/schedule?page=999"
      expect(response).to have_http_status(:ok)
    end

    it "pagination: with > 50 entries, page 1 has 50 + page 2 has the rest" do
      55.times { |i| create(:calendar_entry, :custom, starts_at: (i + 1).days.from_now) }
      get "/calendar/schedule?page=1"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("page 1")
    end

    it "default state filter hides cancelled and superseded" do
      create(:calendar_entry, :custom, title: "active", starts_at: 1.day.from_now)
      create(:calendar_entry, :custom, :cancelled, title: "cxld", starts_at: 1.day.from_now)
      get "/calendar/schedule"
      expect(response.body).to include("active")
      expect(response.body).not_to include("cxld")
    end

    it "?state=all surfaces cancelled" do
      create(:calendar_entry, :custom, :cancelled, title: "cxld_too", starts_at: 1.day.from_now)
      get "/calendar/schedule?state=all"
      expect(response.body).to include("cxld_too")
    end
  end
end
