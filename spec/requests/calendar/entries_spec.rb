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

    # Phase 7.5 §11h — channel-rename-unlock reminder variant. The
    # client (`reminder_link_controller.js`) POSTs a milestone_manual
    # entry with a "Channel <gate> unlock — <name>" title and
    # `all_day: "yes"`. The controller treats the second identical
    # POST as idempotent (no second row, `duplicate: "yes"` marker
    # on the JSON envelope).
    describe "channel-rename-unlock reminder variant" do
      let(:date) { 14.days.from_now.to_date.iso8601 }
      let(:reminder_params) do
        {
          calendar_entry: {
            entry_type: "milestone_manual",
            title: "Channel title unlock — Cached title",
            starts_at: date,
            all_day: "yes",
            timezone: "UTC"
          }
        }
      end

      it "happy: 201 + canonical envelope with the milestone_manual shape" do
        expect {
          post "/calendar/entries.json",
               params: reminder_params.to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.to change(CalendarEntry, :count).by(1)
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["entry"]["entry_type"]).to eq("milestone_manual")
        expect(body["entry"]["all_day"]).to eq("yes")
        expect(body["entry"]["title"]).to eq("Channel title unlock — Cached title")
        expect(body["duplicate"]).to be_nil
      end

      it "edge: rapid second POST is idempotent (no new row, duplicate: yes)" do
        post "/calendar/entries.json",
             params: reminder_params.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:created)

        expect {
          post "/calendar/entries.json",
               params: reminder_params.to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.not_to change(CalendarEntry, :count)
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["duplicate"]).to eq("yes")
      end

      it "edge: a different unlock-date creates a separate row" do
        post "/calendar/entries.json",
             params: reminder_params.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }

        other = reminder_params.deep_dup
        other[:calendar_entry][:starts_at] = (14.days.from_now + 1.day).to_date.iso8601
        expect {
          post "/calendar/entries.json",
               params: other.to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.to change(CalendarEntry, :count).by(1)
        expect(response).to have_http_status(:created)
      end

      it "sad: rejects channel_id (cross-reference validator forbids it on milestone_manual)" do
        bad = reminder_params.deep_dup
        bad[:calendar_entry][:channel_id] = create(:channel).id
        expect {
          post "/calendar/entries.json",
               params: bad.to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.not_to change(CalendarEntry, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
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

  # Calendar refactor 2026-05-11 — details pane for the click-to-open
  # modal on the month grid + schedule list.
  describe "GET /calendar/entries/:id/details_pane" do
    it "renders 200 with the entry's title + typed label" do
      ce = create(:calendar_entry, :milestone_manual, title: "podcast")
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("podcast")
      expect(response.body).to include("milestone")
    end

    it "wraps the body in the matching turbo-frame tag for the modal swap" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include('id="calendar_entry_details_frame"')
    end

    it "renders the `[ all day ]` badge when entry.all_day is true" do
      ce = create(:calendar_entry, :game_release, all_day: true)
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include("[ all day ]")
    end

    it "renders an HH:MM stamp when entry.all_day is false" do
      ce = create(:calendar_entry, :custom,
                  all_day: false,
                  starts_at: Time.zone.parse("2026-05-14 14:30:00 UTC"))
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include("14:30")
    end

    it "renders an `[open video]` link for video_published entries" do
      v = create(:video)
      ce = create(:calendar_entry, :video_published, video_record: v)
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include(">open video<")
      expect(response.body).to include(%(href="/videos/#{v.id}"))
    end

    it "renders an `[open game]` link for game_release entries" do
      g = create(:game)
      ce = create(:calendar_entry, :game_release, game: g)
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include(">open game<")
      expect(response.body).to include(%(href="/games/#{g.id}"))
    end

    it "renders an `[open channel]` link for channel_published entries" do
      ch = create(:channel)
      ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include(">open channel<")
      expect(response.body).to include(%(href="/channels/#{ch.id}"))
    end

    it "falls back to `[open entry]` for free-form types (custom / milestone_manual)" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/calendar/entries/#{ce.id}/details_pane"
      expect(response.body).to include(">open entry<")
    end

    it "renders without the application layout (no nav / no breadcrumb)" do
      ce = create(:calendar_entry, :milestone_manual)
      get "/calendar/entries/#{ce.id}/details_pane"
      # The application layout always emits the `<nav>` shell around
      # the page; the layoutless render skips it.
      expect(response.body).not_to include("<nav")
    end

    it "404s for an unknown id" do
      get "/calendar/entries/0/details_pane"
      expect(response).to have_http_status(:not_found)
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
