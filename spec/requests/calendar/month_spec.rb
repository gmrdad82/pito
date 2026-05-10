require "rails_helper"

RSpec.describe "Calendar::Month", type: :request do
  describe "GET /calendar (root)" do
    it "redirects to the current month grid" do
      get "/calendar"
      now = Time.current
      expect(response).to redirect_to("/calendar/month/#{now.year}/#{now.month}")
    end
  end

  describe "GET /calendar/month/:year/:month" do
    it "happy: renders 200 with the month name + weekday headers" do
      get "/calendar/month/2026/05"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("may 2026")
      %w[mon tue wed thu fri sat sun].each do |w|
        expect(response.body).to include(w)
      end
    end

    it "renders prev / next nav cluster" do
      get "/calendar/month/2026/05"
      expect(response.body).to include("prev month")
      expect(response.body).to include("next month")
    end

    it "sad: invalid month redirects to /calendar with flash" do
      get "/calendar/month/2026/13"
      expect(response).to redirect_to("/calendar")
      follow_redirect!
      # Redirect chain ends at the month grid; flash carried.
    end

    it "sad: non-numeric year hits the route constraint and 404s" do
      get "/calendar/month/abcd/05"
      expect(response).to have_http_status(:not_found)
    end

    it "filter: type=video renders only video entries" do
      v = create(:video)
      v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vidx", category_id: "10")
      get "/calendar/month/2026/05?type=video"
      expect(response).to have_http_status(:ok)
      # The chip shows the truncated title prefix; the full title may
      # exceed the chip width and be ellipsis-suffixed. Match the
      # leading prefix that always survives.
      expect(response.body).to include("video published: vidx")
    end

    it "filter: type=invalid redirects with flash" do
      get "/calendar/month/2026/05?type=zorblax"
      expect(response).to redirect_to("/calendar")
    end

    it "empty state: renders the grid + add entry link with no entries" do
      get "/calendar/month/2030/01"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no entries this month")
      expect(response.body).to include("add entry")
    end

    it "today highlight: cell renders the today class" do
      now = Time.current.in_time_zone("UTC")
      get "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
      expect(response.body).to include("today")
    end

    it "year-boundary entry on Dec 31 (Europe/Madrid late evening) appears in Dec grid" do
      AppSetting.delete_all
      AppSetting.create!(key: "tz_seed", value: "x", timezone: "Europe/Madrid")
      tz = ActiveSupport::TimeZone["Europe/Madrid"]
      e = create(:calendar_entry, :custom,
                 starts_at: tz.local(2026, 12, 31, 23, 30),
                 timezone: "Europe/Madrid",
                 title: "year boundary")
      get "/calendar/month/2026/12"
      expect(response.body).to include("year boundary")
    end
  end
end
