require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Soft-cancel JSON
# shape (locked decision #4).
RSpec.describe "Deletions Calendar Entry JSON", type: :request do
  let(:json) { JSON.parse(response.body) }

  let!(:entry_a) { create(:calendar_entry, entry_type: :milestone_manual, source: :manual, starts_at: 1.day.from_now) }
  let!(:entry_b) { create(:calendar_entry, entry_type: :milestone_manual, source: :manual, starts_at: 2.days.from_now) }

  describe "DELETE /deletions/calendar_entry/:ids.json" do
    it "soft-cancels one entry (happy: single id)" do
      delete "/deletions/calendar_entry/#{entry_a.id}.json"
      expect(response).to have_http_status(:ok)
      expect(json["cancelled"]).to eq([ { "id" => entry_a.id, "state" => "cancelled" } ])
      expect(json["skipped"]).to eq([])
      expect(entry_a.reload.state).to eq("cancelled")
    end

    it "soft-cancels N entries (happy: bulk)" do
      delete "/deletions/calendar_entry/#{entry_a.id},#{entry_b.id}.json"
      expect(response).to have_http_status(:ok)
      ids = json["cancelled"].map { |r| r["id"] }
      expect(ids).to match_array([ entry_a.id, entry_b.id ])
    end

    it "skips already-cancelled entries with reason 'already_cancelled' (edge)" do
      entry_a.update!(state: :cancelled)
      delete "/deletions/calendar_entry/#{entry_a.id},#{entry_b.id}.json"
      expect(response).to have_http_status(:ok)
      expect(json["skipped"]).to include("id" => entry_a.id, "reason" => "already_cancelled")
      expect(json["cancelled"].map { |r| r["id"] }).to eq([ entry_b.id ])
    end

    it "skips derived/auto entries with 'not_user_cancellable' (flaw)" do
      derived = create(:calendar_entry, :video_published)
      delete "/deletions/calendar_entry/#{derived.id},#{entry_a.id}.json"
      expect(response).to have_http_status(:ok)
      expect(json["skipped"]).to include("id" => derived.id, "reason" => "not_user_cancellable")
      expect(json["cancelled"].map { |r| r["id"] }).to eq([ entry_a.id ])
    end

    it "rejects an empty ids list with 422 (sad)" do
      delete "/deletions/calendar_entry/,.json"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "no_ids_supplied")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      delete "/deletions/calendar_entry/#{entry_a.id}.json"
      expect(response).to redirect_to(login_path)
    end
  end
end
