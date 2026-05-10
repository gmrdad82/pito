require "rails_helper"

RSpec.describe "Calendar::Month", type: :request do
  describe "GET /calendar (root)" do
    # Phase 15 calendar UX restructure: `/calendar` now renders a thin
    # client-side router shell (Calendar::RouterController#show) instead
    # of issuing a server-side redirect. The shell carries a meta-refresh
    # fallback to the current month grid for non-JS visits and a Stimulus
    # controller that reads localStorage `pito-calendar-view` to pick
    # between schedule and month for JS-enabled visits.
    it "renders the router shell with both view paths embedded" do
      get "/calendar"
      now = Time.current
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("calendar-view-router")
      expect(response.body).to include("/calendar/month/#{now.year}/#{format('%02d', now.month)}")
      expect(response.body).to include("/calendar/schedule")
    end

    it "carries a meta-refresh fallback to the current month grid" do
      get "/calendar"
      now = Time.current
      expect(response.body).to match(/<meta http-equiv="refresh"[^>]*\/calendar\/month\/#{now.year}\/#{format('%02d', now.month)}/)
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

    it "renders prev / next nav cluster as bare bracketed links (no inner spaces)" do
      get "/calendar/month/2026/05"
      expect(response.body).to include(">prev<")
      expect(response.body).to include(">next<")
    end

    it "breadcrumb_actions slot carries [schedule] and [+] for the month view" do
      get "/calendar/month/2026/05"
      expect(response.body).to include(">schedule<")
      expect(response.body).to include(">+<")
    end

    it "[+] link points at the new calendar entry path" do
      get "/calendar/month/2026/05"
      expect(response.body).to match(/href="\/calendar\/entries\/new"[^>]*>\[<span class="bl">\+/)
    end

    it "sad: invalid month redirects to /calendar with flash" do
      get "/calendar/month/2026/13"
      expect(response).to redirect_to("/calendar")
    end

    it "sad: non-numeric year hits the route constraint and 404s" do
      get "/calendar/month/abcd/05"
      expect(response).to have_http_status(:not_found)
    end

    describe "?types= filter (calendar UX restructure)" do
      it "filter: types=video renders only video entries" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vidx", category_id: "10")
        get "/calendar/month/2026/05?types=video"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("video published: vidx")
      end

      it "filter: no `types` param renders all kinds (default = all checked)" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vid_default", category_id: "10")
        ce = create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "custom_default")
        get "/calendar/month/2026/05"
        expect(response.body).to include("video published: vid_default")
        expect(response.body).to include("custom_default")
      end

      it "filter: types=video,custom renders the union of those kinds" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vid_in_union", category_id: "10")
        create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "custom_in_union")
        create(:calendar_entry, :milestone_manual, starts_at: Time.zone.local(2026, 5, 17, 12, 0), title: "milestone_excluded")
        get "/calendar/month/2026/05?types=video,custom"
        expect(response.body).to include("vid_in_union")
        expect(response.body).to include("custom_in_union")
        expect(response.body).not_to include("milestone_excluded")
      end

      it "filter: empty `types=` (all unchecked) renders no entries" do
        create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "should_be_hidden")
        get "/calendar/month/2026/05?types="
        expect(response.body).to include("no entries this month")
        expect(response.body).not_to include("should_be_hidden")
      end

      it "filter: types=zorblax (all invalid) is treated as all unchecked" do
        get "/calendar/month/2026/05?types=zorblax"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no entries this month")
      end

      it "filter chip URLs round-trip: clicking [video] from default state yields ?types= with all 5 kinds minus video" do
        get "/calendar/month/2026/05"
        # Anchor for `[video]` carries an href pointing at the
        # complement (game,milestone,purchase,custom). The other 4
        # individual chips are listed in CSV order.
        expect(response.body).to match(%r{href="[^"]*types=game%2Cmilestone%2Cpurchase%2Ccustom[^"]*"[^>]*data-keyboard-filter-chip="video"})
      end

      it "filter chip URLs round-trip: with ?types=video the [game] chip's href adds game" do
        get "/calendar/month/2026/05?types=video"
        # `[game]` chip should produce an href with types=video,game.
        expect(response.body).to match(%r{href="[^"]*types=video%2Cgame[^"]*"[^>]*data-keyboard-filter-chip="game"})
      end

      it "[all types] master toggle href clears the param when currently checked (default state)" do
        get "/calendar/month/2026/05"
        expect(response.body).to match(%r{href="[^"]*types=[^,A-Za-z][^"]*"[^>]*data-keyboard-filter-chip="all types"})
      end
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
