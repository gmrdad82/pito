require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Calendar entries CRUD
# JSON surface — exhaustive happy / sad / edge / flaw matrix.
RSpec.describe "Calendar Entries JSON", type: :request do
  let(:json) { JSON.parse(response.body) }

  describe "GET /calendar/entries/:id.json" do
    let(:entry) { create(:calendar_entry, entry_type: :custom, title: "show me") }

    it "returns 200 with detail + dispatch_declarations (happy)" do
      get "/calendar/entries/#{entry.id}.json"
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[entry dispatch_declarations])
      expect(json["entry"]["id"]).to eq(entry.id)
    end

    it "rejects unknown id with 404 (sad)" do
      get "/calendar/entries/999999.json"
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "Not found")
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get "/calendar/entries/#{entry.id}.json"
      expect(response).to redirect_to(login_path)
    end

    it "pins the detail key set (wire-shape snapshot)" do
      get "/calendar/entries/#{entry.id}.json"
      expect(json["entry"].keys).to include(
        "id", "entry_type", "title", "starts_at", "ends_at",
        "all_day", "timezone", "state", "source", "read_only",
        "parent_entry_id", "child_entry_ids", "metadata"
      )
    end
  end

  describe "POST /calendar/entries.json" do
    let(:user) { User.first || create(:user) }

    let(:valid_attrs) do
      {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "ship phase 21",
          starts_at: "2026-06-01T10:00:00Z",
          all_day: "no",
          timezone: "Europe/Bucharest"
        }
      }
    end

    it "creates the entry and returns 201 + detail (happy)" do
      post "/calendar/entries.json", params: valid_attrs.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:created)
      expect(json["entry"]["title"]).to eq("ship phase 21")
    end

    it "rejects an empty payload with 422 (sad)" do
      post "/calendar/entries.json", params: "{}",
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("missing_calendar_entry_payload")
    end

    it "rejects a non-manual entry_type with 422 (sad)" do
      bad = valid_attrs.deep_merge(calendar_entry: { entry_type: "channel_published" })
      post "/calendar/entries.json", params: bad.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("entry_type_not_user_creatable")
    end

    it "rejects malformed yes/no with 422 + envelope (flaw)" do
      bad = valid_attrs.deep_merge(calendar_entry: { all_day: "true" })
      post "/calendar/entries.json", params: bad.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(
        "error" => "invalid_yes_no",
        "field" => "all_day",
        "value" => "true"
      )
    end

    it "returns 422 with validation errors when title is blank (sad)" do
      bad = valid_attrs.deep_merge(calendar_entry: { title: "" })
      post "/calendar/entries.json", params: bad.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to be_a(Hash)
      expect(json["errors"]).to have_key("title")
    end

    it "permits parent_entry_id (locked decision #3)" do
      parent = create(
        :calendar_entry,
        entry_type: :game_release,
        source: :derived,
        title: "released: x",
        starts_at: 1.day.from_now,
        source_ref: { "game_id" => 99 }
      )
      payload = valid_attrs.deep_merge(
        calendar_entry: {
          entry_type: "purchase_planned",
          parent_entry_id: parent.id
        }
      )
      post "/calendar/entries.json", params: payload.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:created)
      expect(json["entry"]["parent_entry_id"]).to eq(parent.id)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      post "/calendar/entries.json", params: valid_attrs.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "PATCH /calendar/entries/:id.json" do
    let!(:entry) do
      create(:calendar_entry,
             entry_type: :milestone_manual,
             title: "old title",
             starts_at: 1.day.from_now,
             source: :manual)
    end

    it "updates and returns the detail (happy)" do
      patch "/calendar/entries/#{entry.id}.json",
            params: { calendar_entry: { title: "new title" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(json["entry"]["title"]).to eq("new title")
    end

    it "rejects read-only entry with 403 (sad)" do
      derived = create(:calendar_entry, :video_published)
      patch "/calendar/entries/#{derived.id}.json",
            params: { calendar_entry: { title: "x" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "read_only_entry")
    end

    it "returns 422 on validation failure (sad)" do
      patch "/calendar/entries/#{entry.id}.json",
            params: { calendar_entry: { title: "" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to have_key("title")
    end

    it "rejects malformed yes/no with 422 (flaw)" do
      patch "/calendar/entries/#{entry.id}.json",
            params: { calendar_entry: { all_day: "1" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_yes_no")
    end
  end

  describe "PATCH /calendar/entries/:id/note.json" do
    let(:derived) { create(:calendar_entry, :video_published) }

    it "writes the note even on a read-only entry (happy)" do
      patch "/calendar/entries/#{derived.id}/note.json",
            params: { calendar_entry: { note: "hello" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(json["entry"]["metadata"]["user_overrides"]["note"]).to eq("hello")
    end

    it "rejects unknown id with 404 (sad)" do
      patch "/calendar/entries/999999/note.json",
            params: { calendar_entry: { note: "x" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
