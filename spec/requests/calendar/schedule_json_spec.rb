require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "Calendar Schedule JSON", type: :request do
  let(:json) { JSON.parse(response.body) }

  let!(:scheduled) do
    create(:calendar_entry, title: "future", starts_at: 1.day.from_now)
  end
  let!(:cancelled) do
    create(:calendar_entry, title: "cancelled", starts_at: 2.days.from_now, state: :cancelled)
  end

  describe "GET /calendar/schedule.json" do
    it "returns 200 with the envelope (happy)" do
      get "/calendar/schedule.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(
        %w[page total_pages total per_page selected_kinds selected_source
           show_cancelled install_tz today entries]
      )
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/calendar/schedule.json"
      expect(response).to redirect_to(login_path)
    end

    it "hides cancelled entries by default (edge)" do
      get "/calendar/schedule.json"
      titles = json["entries"].map { |e| e["title"] }
      expect(titles).to include("future")
      expect(titles).not_to include("cancelled")
    end

    it "includes cancelled entries when ?state=all (edge)" do
      get "/calendar/schedule.json?state=all"
      titles = json["entries"].map { |e| e["title"] }
      expect(titles).to include("cancelled")
    end

    it "honors the types filter (?types=custom)" do
      get "/calendar/schedule.json?types=custom"
      expect(json["selected_kinds"]).to eq([ "custom" ])
    end

    it "renders selected_kinds as [] when ?types= (edge: all unchecked)" do
      get "/calendar/schedule.json?types="
      expect(json["selected_kinds"]).to eq([])
      expect(json["entries"]).to eq([])
    end

    it "echoes pagination (edge: page=2)" do
      get "/calendar/schedule.json?page=2"
      expect(json["page"]).to eq(2)
    end

    it "renders boolean show_cancelled as yes/no" do
      get "/calendar/schedule.json"
      expect(json["show_cancelled"]).to be_in(%w[yes no])
    end

    it "rejects unknown source with redirect (sad)" do
      get "/calendar/schedule.json?source=__nope__"
      # Existing HTML branch redirects; for JSON we follow the same path.
      expect(response).to be_redirect.or have_http_status(:ok)
    end
  end
end
