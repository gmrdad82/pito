require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "Calendar Month JSON", type: :request do
  let(:json) { JSON.parse(response.body) }

  let!(:entry) do
    create(:calendar_entry,
           title: "in-month entry",
           starts_at: Time.zone.parse("2026-05-13T17:00:00Z"))
  end

  describe "GET /calendar/month/:year/:month.json" do
    it "returns 200 with the envelope (happy)" do
      get "/calendar/month/2026/5.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(
        %w[year month install_tz first_day last_day today
           on_current_month selected_kinds show_cancelled buckets nav]
      )
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/calendar/month/2026/5.json"
      expect(response).to redirect_to(login_path)
    end

    it "bucks entries by ISO date (edge)" do
      get "/calendar/month/2026/5.json"
      expect(json["buckets"]).to have_key("2026-05-13")
    end

    it "rejects invalid month with redirect (sad)" do
      get "/calendar/month/2026/14.json"
      expect(response).to be_redirect
    end

    it "renders nav prev across the year boundary (edge: Jan)" do
      get "/calendar/month/2026/1.json"
      expect(json["nav"]["prev"]).to eq("year" => 2025, "month" => 12)
    end

    it "renders nav next across the year boundary (edge: Dec)" do
      get "/calendar/month/2026/12.json"
      expect(json["nav"]["next"]).to eq("year" => 2027, "month" => 1)
    end

    it "serializes on_current_month / show_cancelled as yes/no" do
      get "/calendar/month/2026/5.json"
      expect(json["on_current_month"]).to be_in(%w[yes no])
      expect(json["show_cancelled"]).to be_in(%w[yes no])
    end

    it "renders selected_kinds as [] when ?types= empty (edge)" do
      get "/calendar/month/2026/5.json?types="
      expect(json["selected_kinds"]).to eq([])
      expect(json["buckets"]).to eq({})
    end
  end
end
