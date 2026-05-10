require "rails_helper"

# Phase 15 calendar UX restructure — `/calendar` view-persistence router.
#
# The route used to be a server-side redirect to the current month grid.
# It now renders a thin client-side router shell that defers the choice
# of view to JS (localStorage `pito-calendar-view` → schedule or month).
# A `<meta http-equiv="refresh">` carries the no-JS fallback to the
# month grid.
RSpec.describe "Calendar::Router", type: :request do
  describe "GET /calendar" do
    it "responds 200 (no longer a server-side redirect)" do
      get "/calendar"
      expect(response).to have_http_status(:ok)
    end

    it "embeds the calendar-view-router Stimulus controller hook" do
      get "/calendar"
      expect(response.body).to include("data-controller=\"calendar-view-router\"")
    end

    it "exposes both target paths to the JS controller via data-* values" do
      get "/calendar"
      now = Time.current
      expect(response.body).to include("data-calendar-view-router-month-path-value=\"/calendar/month/#{now.year}/#{format('%02d', now.month)}\"")
      expect(response.body).to include("data-calendar-view-router-schedule-path-value=\"/calendar/schedule\"")
    end

    it "carries a meta-refresh fallback to the month grid for non-JS clients" do
      get "/calendar"
      now = Time.current
      expect(response.body).to match(/<meta http-equiv="refresh" content="\d+; url=\/calendar\/month\/#{now.year}\/#{format('%02d', now.month)}"/)
    end

    it "renders without the application chrome (no-layout shell)" do
      get "/calendar"
      # The shell is intentionally bare — no nav bar, no footer — so
      # the JS-side replace cannot flash chrome before redirecting.
      expect(response.body).not_to include("Sidekiq::Web")
      # The shell renders its own minimal `<title>`, not the layout's.
      expect(response.body).to include("<title>calendar ~ pito</title>")
    end
  end
end
