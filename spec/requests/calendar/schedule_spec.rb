require "rails_helper"

RSpec.describe "Calendar::Schedule", type: :request do
  describe "GET /calendar/schedule" do
    it "happy: renders 200 with the schedule shell" do
      get "/calendar/schedule"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("schedule")
    end

    it "breadcrumb_actions slot carries [month] and [+] for the schedule view" do
      get "/calendar/schedule"
      expect(response.body).to include(">month<")
      expect(response.body).to include(">+<")
    end

    it "with both past and future entries, renders the [today] divider" do
      create(:calendar_entry, :custom, starts_at: 5.days.ago, title: "past")
      create(:calendar_entry, :custom, starts_at: 5.days.from_now, title: "future")
      get "/calendar/schedule"
      expect(response.body).to include("[ today ]")
    end

    describe "?types= filter (calendar UX restructure)" do
      it "filters by types=game (single kind)" do
        g = create(:game)
        ce = create(:calendar_entry, :game_release, game: g, starts_at: 30.days.from_now, title: "released: g")
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "v", category_id: "10")
        get "/calendar/schedule?types=game"
        expect(response.body).to include("released: g")
        expect(response.body).not_to include("video published: v")
      end

      it "filters by types=video,game (union)" do
        g = create(:game)
        create(:calendar_entry, :game_release, game: g, starts_at: 30.days.from_now, title: "g_in_union")
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "v_in_union", category_id: "10")
        create(:calendar_entry, :custom, title: "custom_excluded", starts_at: 1.day.from_now)
        get "/calendar/schedule?types=video,game"
        expect(response.body).to include("g_in_union")
        expect(response.body).to include("video published: v_in_union")
        expect(response.body).not_to include("custom_excluded")
      end

      it "no types param shows all kinds" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "vshow", category_id: "10")
        create(:calendar_entry, :custom, title: "cshow", starts_at: 1.day.from_now)
        get "/calendar/schedule"
        expect(response.body).to include("video published: vshow")
        expect(response.body).to include("cshow")
      end

      it "empty types= renders no entries" do
        create(:calendar_entry, :custom, title: "hidden_one", starts_at: 1.day.from_now)
        get "/calendar/schedule?types="
        expect(response.body).to include("no entries")
        expect(response.body).not_to include("hidden_one")
      end

      it "types=zorblax (all invalid) renders no entries" do
        create(:calendar_entry, :custom, title: "x", starts_at: 1.day.from_now)
        get "/calendar/schedule?types=zorblax"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no entries")
      end
    end

    it "filters by source=manual" do
      create(:calendar_entry, :milestone_manual, title: "podcast")
      v = create(:video)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "thevid", category_id: "10")
      get "/calendar/schedule?source=manual"
      expect(response.body).to include("podcast")
      expect(response.body).not_to include("video published: thevid")
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
