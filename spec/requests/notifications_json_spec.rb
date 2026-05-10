require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Notifications JSON
# surface — exhaustive happy / sad / edge / flaw matrix.
RSpec.describe "Notifications JSON", type: :request do
  let(:json) { JSON.parse(response.body) }

  let!(:unread_a) { create(:notification, :video_published, last_error: "boom") }
  let!(:unread_b) { create(:notification, :sync_error) }
  let!(:read_a)   { create(:notification, :read, :calendar_entry_firing) }

  describe "GET /notifications.json" do
    it "returns 200 with the envelope (happy)" do
      get "/notifications.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(
        %w[page total_pages total per_page filter kind severity
           unread_count has_failures notifications]
      )
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/notifications.json"
      expect(response).to redirect_to(login_path)
    end

    it "reports has_failures = yes when an unread row has last_error (edge)" do
      get "/notifications.json"
      expect(json["has_failures"]).to eq("yes")
    end

    it "filter=unread returns only unread rows" do
      get "/notifications.json?filter=unread"
      ids = json["notifications"].map { |n| n["id"] }
      expect(ids).to include(unread_a.id, unread_b.id)
      expect(ids).not_to include(read_a.id)
    end

    it "kind=sync_error filters by kind" do
      get "/notifications.json?kind=sync_error"
      ids = json["notifications"].map { |n| n["id"] }
      expect(ids).to include(unread_b.id)
      expect(ids).not_to include(unread_a.id)
    end

    it "echoes pagination (edge: page=2)" do
      get "/notifications.json?page=2"
      expect(json["page"]).to eq(2)
    end

    it "renders each row with the summary key set (wire-shape snapshot)" do
      get "/notifications.json"
      expect(json["notifications"].first.keys).to match_array(
        %w[id kind severity event_type title body url fires_at
           in_app_read_at read discord_delivered_at slack_delivered_at
           retry_count last_error created_at]
      )
    end
  end

  describe "GET /notifications/:id.json" do
    it "returns 200 with notification + payload (happy)" do
      get "/notifications/#{unread_a.id}.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[notification payload])
      expect(json["notification"]["id"]).to eq(unread_a.id)
    end

    it "rejects unknown id with 404 (sad)" do
      get "/notifications/999999.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notifications/badge.json" do
    it "returns 200 with { unread_count, has_failures } (happy)" do
      get "/notifications/badge.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[unread_count has_failures])
      expect(json["unread_count"]).to eq(2)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/notifications/badge.json"
      expect(response).to redirect_to(login_path)
    end

    it "serializes has_failures as yes/no" do
      get "/notifications/badge.json"
      expect(json["has_failures"]).to be_in(%w[yes no])
    end

    it "returns has_failures = no when there are no error rows (edge)" do
      Notification.update_all(last_error: nil)
      get "/notifications/badge.json"
      expect(json["has_failures"]).to eq("no")
    end
  end

  describe "PATCH /notifications/:id/read.json" do
    it "returns 200 + body (locked decision #2)" do
      patch "/notifications/#{unread_a.id}/read.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[id read in_app_read_at unread_count])
      expect(json["read"]).to eq("yes")
      expect(json["unread_count"]).to eq(1)
    end

    it "is idempotent on an already-read row (edge)" do
      patch "/notifications/#{read_a.id}/read.json"
      expect(response).to have_http_status(:ok)
      expect(json["read"]).to eq("yes")
    end

    it "rejects unknown id with 404 (sad)" do
      patch "/notifications/999999/read.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /notifications/:id/unread.json" do
    it "returns 200 + body (locked decision #2)" do
      patch "/notifications/#{read_a.id}/unread.json"
      expect(response).to have_http_status(:ok)
      expect(json["read"]).to eq("no")
      expect(json["in_app_read_at"]).to be_nil
      expect(json["unread_count"]).to eq(3)
    end
  end

  describe "PATCH /notifications/mark_read.json" do
    it "returns 200 + body (happy: ids list)" do
      patch "/notifications/mark_read.json?ids=#{unread_a.id},#{unread_b.id}"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[marked unread_count has_failures])
      expect(json["marked"]).to eq(2)
      expect(json["unread_count"]).to eq(0)
    end

    it "rejects empty ids with 422 + no_ids_supplied (sad)" do
      patch "/notifications/mark_read.json?ids="
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "no_ids_supplied")
    end

    it "returns 429 on the rate-limited path (flaw)" do
      # Swap the null_store for an in-memory store so the lock actually
      # persists across the test boundary (mirrors the pattern in
      # `spec/requests/notifications_spec.rb`).
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      memory_cache.write("notifications:mark_read:user:#{User.first.id}", 1, expires_in: 5.seconds)

      patch "/notifications/mark_read.json?ids=#{unread_a.id}"
      expect(response).to have_http_status(:too_many_requests)
      expect(json).to include("error" => "rate_limited")
    end
  end

  describe "PATCH /notifications/mark_all_read.json" do
    it "marks every unread row + returns 200 (happy)" do
      patch "/notifications/mark_all_read.json"
      expect(response).to have_http_status(:ok)
      expect(json["unread_count"]).to eq(0)
      expect(json["marked"]).to eq(2)
    end

    it "is idempotent on a clean inbox (edge)" do
      Notification.update_all(in_app_read_at: Time.current)
      patch "/notifications/mark_all_read.json"
      expect(response).to have_http_status(:ok)
      expect(json["marked"]).to eq(0)
    end
  end
end
