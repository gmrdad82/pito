require "rails_helper"

RSpec.describe "Calendar::Month", type: :request do
  describe "GET /calendar (root)" do
    # Phase 15 calendar UX restructure: `/calendar` now renders a thin
    # client-side router shell (Calendar::RouterController#show) instead
    # of issuing a server-side redirect. The shell carries a meta-refresh
    # fallback to the current month grid for non-JS visits and a Stimulus
    # controller that reads localStorage `pito-calendar-view` to pick
    # between schedule and month for JS-enabled visits.
    it "renders the router shell with both view paths embedded" do
      get "/calendar"
      now = Time.current
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("calendar-view-router")
      expect(response.body).to include("/calendar/month/#{now.year}/#{format('%02d', now.month)}")
      expect(response.body).to include("/calendar/schedule")
    end

    it "carries a meta-refresh fallback to the current month grid" do
      get "/calendar"
      now = Time.current
      expect(response.body).to match(/<meta http-equiv="refresh"[^>]*\/calendar\/month\/#{now.year}\/#{format('%02d', now.month)}/)
    end
  end

  describe "GET /calendar/month/:year/:month" do
    it "happy: renders 200 with the month name + weekday headers" do
      get "/calendar/month/2026/05"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("may 2026")
      %w[mon tue wed thu fri sat sun].each do |w|
        expect(response.body).to include(w)
      end
    end

    it "renders prev / next nav cluster as bare bracketed links (no inner spaces)" do
      get "/calendar/month/2026/05"
      expect(response.body).to include(">prev<")
      expect(response.body).to include(">next<")
    end

    it "breadcrumb_actions slot carries [schedule] and [+] for the month view" do
      get "/calendar/month/2026/05"
      expect(response.body).to include(">schedule<")
      expect(response.body).to include(">+<")
    end

    # Phase 15 calendar UX restructure — breadcrumb segment flip
    # (2026-05-10). On the month view the active-view label is the
    # current month name (e.g. `[may 2026]`), rendered as plain text
    # via `<span class="bracketed-active">`. The `[schedule]` segment
    # is the link toggle to the schedule view (asserted elsewhere).
    it "[may 2026] active label is a plain span (no link)" do
      get "/calendar/month/2026/05"
      expect(response.body).to match(
        %r{<span class="bracketed-active">\[may 2026\]</span>}
      )
      # And critically, no `<a>` tag wraps the `may 2026` label.
      expect(response.body).not_to match(
        %r{<a [^>]*>\[<span class="bl">may 2026</span>\]</a>}
      )
    end

    # Placement check: the rendered breadcrumb row reads
    # `[calendar] / [may 2026] · [schedule] [+]`. Locking the document
    # order catches a future refactor that misplaces a slot (e.g.
    # drops the active label out of the breadcrumbs slot).
    it "renders breadcrumb segments in [calendar] / [may 2026] · [schedule] [+] order" do
      get "/calendar/month/2026/05"
      cal_pos      = response.body.index('<span class="bl">calendar</span>')
      month_pos    = response.body.index('<span class="bracketed-active">[may 2026]</span>')
      schedule_pos = response.body.index('<span class="bl">schedule</span>')
      plus_pos     = response.body.index('<span class="bl">+</span>')
      expect(cal_pos).not_to be_nil
      expect(month_pos).not_to be_nil
      expect(schedule_pos).not_to be_nil
      expect(plus_pos).not_to be_nil
      expect(cal_pos).to be < month_pos
      expect(month_pos).to be < schedule_pos
      expect(schedule_pos).to be < plus_pos
    end

    # Regression: the [schedule] toggle link must target
    # `/calendar/schedule` directly, NOT `/calendar` (which is the
    # view-persistence router). It also carries the `persistSchedule`
    # Stimulus action so subsequent fresh `/calendar` visits honor the
    # toggle.
    it "[schedule] toggle targets /calendar/schedule with persist action" do
      get "/calendar/month/2026/05"
      # ERB escapes `->` in the rendered `data-action` to `-&gt;`.
      # Rails `link_to` attribute ordering is not strictly guaranteed,
      # so assert the three required pieces (href, class, data-action)
      # all live on the same single `<a>` tag whose body is the
      # `[schedule]` label, without pinning their order.
      expect(response.body).to match(
        %r{<a\b(?=[^>]*\bhref="/calendar/schedule")(?=[^>]*\bclass="bracketed")(?=[^>]*\bdata-action="click-&gt;calendar-view-router#persistSchedule")[^>]*>\[<span class="bl">schedule}
      )
    end

    it "[schedule] toggle is wrapped by a `calendar-view-router` controller mount" do
      get "/calendar/month/2026/05"
      expect(response.body).to match(
        %r{<span data-controller="calendar-view-router">\s*<a [^>]*href="/calendar/schedule"[^>]*>\[<span class="bl">schedule}
      )
    end

    it "[+] is a POST `button_to` to /calendar/entries (default-create per Projects pattern)" do
      get "/calendar/month/2026/05"
      # `button_to` renders a `<form method="post">` wrapping a
      # `<button class="bracketed">`. The form's `action` is the create
      # endpoint and the `data-turbo="false"` attribute forces a full
      # navigation so the controller redirect lands on the edit page.
      expect(response.body).to include(%(action="/calendar/entries"))
      expect(response.body).to match(
        %r{<form[^>]*data-turbo="false"[^>]*method="post"[^>]*action="/calendar/entries"[^>]*>\s*<button[^>]*class="bracketed"[^>]*>\[<span class="bl">\+</span>\]</button>\s*</form>}
      )
    end

    it "sad: invalid month redirects to /calendar with flash" do
      get "/calendar/month/2026/13"
      expect(response).to redirect_to("/calendar")
    end

    it "sad: non-numeric year hits the route constraint and 404s" do
      get "/calendar/month/abcd/05"
      expect(response).to have_http_status(:not_found)
    end

    describe "?types= filter (calendar UX restructure)" do
      it "filter: types=video renders only video entries" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vidx", category_id: "10")
        get "/calendar/month/2026/05?types=video"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("video published: vidx")
      end

      it "filter: no `types` param renders all kinds (default = all checked)" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "vd", category_id: "10")
        ce = create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "custom_default")
        get "/calendar/month/2026/05"
        expect(response.body).to include("video published: vd")
        expect(response.body).to include("custom_default")
      end

      it "filter: types=video,custom renders the union of those kinds" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: Date.new(2026, 5, 15).in_time_zone("UTC"), title: "viu", category_id: "10")
        create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "custom_in_union")
        create(:calendar_entry, :milestone_manual, starts_at: Time.zone.local(2026, 5, 17, 12, 0), title: "milestone_excluded")
        get "/calendar/month/2026/05?types=video,custom"
        expect(response.body).to include("video published: viu")
        expect(response.body).to include("custom_in_union")
        expect(response.body).not_to include("milestone_excluded")
      end

      it "filter: empty `types=` (all unchecked) renders no entries" do
        create(:calendar_entry, :custom, starts_at: Time.zone.local(2026, 5, 16, 12, 0), title: "should_be_hidden")
        get "/calendar/month/2026/05?types="
        expect(response.body).to include("no entries this month")
        expect(response.body).not_to include("should_be_hidden")
      end

      it "filter: types=zorblax (all invalid) is treated as all unchecked" do
        get "/calendar/month/2026/05?types=zorblax"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no entries this month")
      end

      it "filter chip URLs round-trip: clicking [video] from default state yields ?types= with all 5 kinds minus video" do
        get "/calendar/month/2026/05"
        # Anchor for `[video]` carries an href pointing at the
        # complement (game,milestone,purchase,custom). The other 4
        # individual chips are listed in CSV order.
        expect(response.body).to match(%r{href="[^"]*types=game%2Cmilestone%2Cpurchase%2Ccustom[^"]*"[^>]*data-keyboard-filter-chip="video"})
      end

      it "filter chip URLs round-trip: with ?types=video the [game] chip's href adds game" do
        get "/calendar/month/2026/05?types=video"
        # `[game]` chip should produce an href with types=video,game.
        expect(response.body).to match(%r{href="[^"]*types=video%2Cgame[^"]*"[^>]*data-keyboard-filter-chip="game"})
      end

      it "[all] master toggle href clears the param when currently checked (default state)" do
        get "/calendar/month/2026/05"
        expect(response.body).to match(%r{href="[^"]*types=[^,A-Za-z][^"]*"[^>]*data-keyboard-filter-chip="all"})
      end
    end

    it "empty state: renders the grid with no entries (no add entry link)" do
      get "/calendar/month/2030/01"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no entries this month.")
      # The breadcrumb [+] is the only add affordance; no inline `add entry`
      # link in the empty-state copy itself.
      expect(response.body).not_to match(/no entries this month[^.]*add entry/)
    end

    # Calendar refactor 2026-05-11 — month grid renders typed token
    # labels (`channel(joined)`, `game(released)`, `milestone`,
    # `video(published)`) in place of the legacy single-letter glyph
    # prefixes (`c:` / `g:` / `m:` / `v:` / `~:`).
    describe "calendar refactor 2026-05-11 — typed labels + modal" do
      it "renders typed token labels for visible entries (no legacy glyph prefix)" do
        create(:calendar_entry, :milestone_manual,
               starts_at: Time.zone.local(2026, 5, 15, 12, 0),
               title: "podcast")
        get "/calendar/month/2026/05"
        expect(response.body).to include("milestone")
        expect(response.body).not_to match(/<span class="calendar-entry__glyph">m:</)
      end

      it "renders a typed `video(published)` label on derived video entries" do
        v = create(:video)
        v.update!(privacy_status: :public,
                  published_at: Date.new(2026, 5, 15).in_time_zone("UTC"),
                  title: "yt-vid",
                  category_id: "10")
        get "/calendar/month/2026/05"
        expect(response.body).to include("video(published)")
      end

      it "chips wire the calendar-entry-modal#open action" do
        create(:calendar_entry, :milestone_manual,
               starts_at: Time.zone.local(2026, 5, 15, 12, 0))
        get "/calendar/month/2026/05"
        # ERB attribute serialization escapes `->` to `-&gt;` only when
        # the attribute is built via the `data:` hash helper (the
        # notifications modal uses that path). The calendar chip
        # renders raw `data-action="..."` so the literal `->` is what
        # ships. Accept either form so the spec is robust to the
        # implementation detail.
        expect(response.body).to match(%r{data-action="click(-&gt;|->)calendar-entry-modal#open"})
        expect(response.body).to match(%r{data-calendar-entry-modal-url-param="/calendar/entries/\d+/details_pane"})
      end

      it "mounts the layout-level calendar-entry-modal dialog once" do
        get "/calendar/month/2026/05"
        expect(response.body).to include("calendar-entry-modal")
        expect(response.body).to include("calendar_entry_details_frame")
      end
    end

    # Calendar polish 2026-05-11 — month grid cells are forced to a
    # 1:1 aspect ratio so the rendered grid is a square mesh
    # regardless of viewport width. Content that doesn't fit is
    # clipped (`overflow: hidden`) — we'll revisit overflow handling
    # later.
    describe "calendar polish 2026-05-11 — square cells" do
      it "each `.calendar-cell` carries aspect-ratio: 1 / 1 on its inline style" do
        get "/calendar/month/2026/05"
        # Pin both: the class hook AND the inline style attribute
        # carrying `aspect-ratio: 1 / 1` so future style refactors
        # can't silently lose the constraint.
        expect(response.body).to match(
          %r{<td class="calendar-cell[^"]*"[^>]*style="[^"]*aspect-ratio:\s*1\s*/\s*1[^"]*"}
        )
      end

      it "each `.calendar-cell` carries overflow: hidden so content clips" do
        get "/calendar/month/2026/05"
        expect(response.body).to match(
          %r{<td class="calendar-cell[^"]*"[^>]*style="[^"]*overflow:\s*hidden[^"]*"}
        )
      end

      it "no longer pins a fixed pixel height (height: 90px) on cells" do
        get "/calendar/month/2026/05"
        expect(response.body).not_to match(
          %r{<td class="calendar-cell[^"]*"[^>]*style="[^"]*height:\s*90px}
        )
      end
    end

    it "today highlight: cell renders the today class" do
      now = Time.current.in_time_zone("UTC")
      get "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
      expect(response.body).to include("today")
    end

    it "year-boundary entry on Dec 31 (Europe/Madrid late evening) appears in Dec grid" do
      AppSetting.delete_all
      AppSetting.create!(key: "tz_seed", value: "x", timezone: "Europe/Madrid")
      tz = ActiveSupport::TimeZone["Europe/Madrid"]
      e = create(:calendar_entry, :custom,
                 starts_at: tz.local(2026, 12, 31, 23, 30),
                 timezone: "Europe/Madrid",
                 title: "year boundary")
      get "/calendar/month/2026/12"
      expect(response.body).to include("year boundary")
    end
  end
end
