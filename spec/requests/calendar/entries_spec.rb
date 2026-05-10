require "rails_helper"

RSpec.describe "Calendar::Entries", type: :request do
  describe "GET /calendar/entries/new" do
    it "renders the form" do
      get "/calendar/entries/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("title")
    end
  end

  describe "GET /calendar/entries/quick_add" do
    it "renders the quick-add form" do
      get "/calendar/entries/quick_add"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /calendar/entries" do
    it "happy: persists a milestone_manual entry" do
      params = {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "podcast appearance",
          description: "guest spot",
          starts_at: 1.day.from_now,
          all_day: "no",
          timezone: "UTC"
        }
      }
      expect {
        post "/calendar/entries", params: params
      }.to change(CalendarEntry, :count).by(1)
      ce = CalendarEntry.where(entry_type: :milestone_manual).last
      expect(ce.title).to eq("podcast appearance")
      expect(response).to redirect_to(calendar_entry_path(ce))
    end

    it "happy: persists a game_release with a game_id" do
      g = create(:game)
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "game_release",
          title: "released: x",
          starts_at: 30.days.from_now,
          all_day: "yes",
          timezone: "UTC",
          game_id: g.id
        }
      }
      expect(response).to redirect_to(calendar_entry_path(CalendarEntry.last))
    end

    it "happy: persists a purchase_planned with parent_entry_id" do
      parent = create(:calendar_entry, :game_release)
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "purchase_planned",
          title: "preorder",
          starts_at: 30.days.from_now,
          all_day: "no",
          timezone: "UTC",
          parent_entry_id: parent.id
        }
      }
      expect(response).to redirect_to(calendar_entry_path(CalendarEntry.last))
    end

    it "sad: rejects entry_type=video_published (derived types not user-creatable)" do
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "video_published",
          title: "x",
          starts_at: 1.day.from_now,
          all_day: "no",
          timezone: "UTC"
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("not user-creatable")
    end

    it "sad: missing title re-renders with validation error" do
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "",
          starts_at: 1.day.from_now,
          all_day: "no",
          timezone: "UTC"
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sad: ends_at < starts_at re-renders" do
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "bad",
          starts_at: 5.days.from_now,
          ends_at: 1.day.from_now,
          all_day: "no",
          timezone: "UTC"
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sad: yes/no smuggling — true/false rejected per CLAUDE.md hard rule" do
      post "/calendar/entries", params: {
        calendar_entry: {
          entry_type: "milestone_manual",
          title: "x",
          starts_at: 1.day.from_now,
          all_day: "true",
          timezone: "UTC"
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("yes")
    end
  end

  describe "GET /calendar/entries/:id" do
    it "renders the entry detail" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/calendar/entries/#{ce.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ce.title)
    end

    it "purchase_planned shows parent_entry link" do
      parent = create(:calendar_entry, :game_release, title: "released: P")
      child = create(:calendar_entry, :purchase_planned, parent_entry: parent)
      get "/calendar/entries/#{child.id}"
      expect(response.body).to include("released: P")
    end

    it "milestone_auto shows milestone_rule + metric_value_at_fire" do
      rule = create(:milestone_rule, name: "100 subs")
      ce = create(:calendar_entry, :milestone_auto, milestone_rule: rule)
      get "/calendar/entries/#{ce.id}"
      expect(response.body).to include("100 subs")
      expect(response.body).to include("100000")
    end
  end

  describe "GET /calendar/entries/:id/edit" do
    it "happy: renders for manual entries" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/calendar/entries/#{ce.id}/edit"
      expect(response).to have_http_status(:ok)
    end

    it "sad: redirects with flash for derived entries" do
      ce = create(:calendar_entry, :video_published)
      get "/calendar/entries/#{ce.id}/edit"
      expect(response).to redirect_to(calendar_entry_path(ce))
    end
  end

  describe "PATCH /calendar/entries/:id" do
    it "happy: updates the entry" do
      ce = create(:calendar_entry, :milestone_manual)
      patch "/calendar/entries/#{ce.id}", params: {
        calendar_entry: { title: "renamed", all_day: "no", timezone: "UTC" }
      }
      expect(response).to redirect_to(calendar_entry_path(ce))
      expect(ce.reload.title).to eq("renamed")
    end

    it "sad: rejects updates to derived entries" do
      ce = create(:calendar_entry, :video_published)
      patch "/calendar/entries/#{ce.id}", params: {
        calendar_entry: { title: "hijacked", all_day: "no", timezone: "UTC" }
      }
      expect(response).to redirect_to(calendar_entry_path(ce))
      expect(ce.reload.title).not_to eq("hijacked")
    end
  end

  describe "PATCH /calendar/entries/:id/note" do
    it "allows note on derived entries via metadata.user_overrides" do
      ce = create(:calendar_entry, :video_published)
      patch "/calendar/entries/#{ce.id}/note", params: {
        calendar_entry: { note: "private comment" }
      }
      expect(response).to redirect_to(calendar_entry_path(ce))
      expect(ce.reload.metadata.dig("user_overrides", "note")).to eq("private comment")
    end
  end
end
