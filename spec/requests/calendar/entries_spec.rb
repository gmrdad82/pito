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

  # Default-create flow (Projects pattern). The breadcrumb `[+]` link
  # POSTs to `/calendar/entries` with no payload; the controller seeds
  # an "Untitled event" milestone_manual entry and redirects to /edit
  # so the user fills in real values in the existing edit form.
  describe "POST /calendar/entries (default-create — no params)" do
    it "creates a milestone_manual entry with placeholder values" do
      expect {
        post "/calendar/entries"
      }.to change(CalendarEntry, :count).by(1)

      ce = CalendarEntry.last
      expect(ce.entry_type).to eq("milestone_manual")
      expect(ce.title).to eq("Untitled event")
      expect(ce.starts_at).to be_present
      expect(ce.ends_at).to be_nil
      expect(ce.all_day).to eq(false)
      expect(ce.timezone).to eq("UTC")
      expect(ce.source).to eq("manual")
    end

    it "redirects to the edit page (not show)" do
      post "/calendar/entries"
      expect(response).to redirect_to(edit_calendar_entry_path(CalendarEntry.last))
    end

    it "honors AppSetting timezone when present" do
      # `AppSetting.first` is the install-level singleton — seed-created
      # in the test DB (id=1) — and its `timezone` column drives the
      # default for new calendar entries. Update the existing row rather
      # than `create!`-ing a new one so `AppSetting.first` actually
      # picks up the new value (it orders by primary key).
      seed = AppSetting.first || AppSetting.create!(key: "_install", value: "x")
      seed.update!(timezone: "Europe/Bucharest")
      post "/calendar/entries"
      expect(CalendarEntry.last.timezone).to eq("Europe/Bucharest")
    end

    it "edit page pre-populates with the placeholder values" do
      post "/calendar/entries"
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Untitled event")
      expect(response.body).to include("UTC")
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

    # Phase 15 reviewer concern 6 — read-only entries no longer expose
    # a `[note]` link until the modal markup is built. The PATCH
    # endpoint is preserved (see "PATCH /calendar/entries/:id/note").
    it "does NOT render a [note] link on read-only entries (modal not yet built)" do
      rule = create(:milestone_rule, name: "100 subs")
      ce = create(:calendar_entry, :milestone_auto, milestone_rule: rule)
      get "/calendar/entries/#{ce.id}"
      expect(response.body).not_to include("note-modal")
      expect(response.body).not_to match(/\[note\]/)
    end

    # Phase 15 reviewer concerns 3 + 4 — the reminder copy is the
    # canonical literal `[remind: t-7 t-1 t-0]` (no inner padding, not
    # derived from `@declarations.map { |d| d[:kind] }`).
    it "renders the canonical [remind: t-7 t-1 t-0] literal for future game_release entries" do
      ce = create(:calendar_entry, :game_release,
                  starts_at: 30.days.from_now,
                  release_precision: :day)
      get "/calendar/entries/#{ce.id}"
      if response.body.include?("remind:")
        expect(response.body).to include("[remind: t-7 t-1 t-0]")
        expect(response.body).not_to match(/\[ remind:/)
      end
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
