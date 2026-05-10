require "rails_helper"

RSpec.describe "Deletions::CalendarEntry", type: :request do
  describe "GET /deletions/calendar_entry/:ids" do
    it "renders the action-screen with cancel copy (singular)" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/deletions/calendar_entry/#{ce.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cancel calendar entry?")
      expect(response.body).to include(ce.title)
    end

    it "renders the action-screen with cancel copy (bulk)" do
      ce1 = create(:calendar_entry, :milestone_manual, title: "alpha")
      ce2 = create(:calendar_entry, :milestone_manual, title: "beta")
      get "/deletions/calendar_entry/#{ce1.id},#{ce2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cancel 2 calendar entries?")
    end

    it "filters out derived entries even if requested directly via URL" do
      manual = create(:calendar_entry, :milestone_manual, title: "manual")
      derived = create(:calendar_entry, :video_published)
      get "/deletions/calendar_entry/#{manual.id},#{derived.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("manual")
      # Derived entry's title should NOT appear in the cancel list.
      expect(response.body).not_to include(derived.title)
    end
  end

  describe "DELETE /deletions/calendar_entry/:ids" do
    it "flips state to :cancelled and redirects to schedule" do
      ce = create(:calendar_entry, :milestone_manual)
      delete "/deletions/calendar_entry/#{ce.id}"
      expect(response).to redirect_to(calendar_schedule_path)
      expect(ce.reload.state).to eq("cancelled")
    end

    it "is bulk-as-foundation: 2 ids cancels both" do
      ce1 = create(:calendar_entry, :milestone_manual)
      ce2 = create(:calendar_entry, :milestone_manual)
      delete "/deletions/calendar_entry/#{ce1.id},#{ce2.id}"
      expect(response).to redirect_to(calendar_schedule_path)
      expect(ce1.reload.state).to eq("cancelled")
      expect(ce2.reload.state).to eq("cancelled")
    end
  end
end
