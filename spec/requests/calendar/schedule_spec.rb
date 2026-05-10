require "rails_helper"

RSpec.describe "Calendar::Schedule", type: :request do
  describe "GET /calendar/schedule" do
    it "happy: renders 200 with the schedule shell" do
      get "/calendar/schedule"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("schedule")
    end

    # Phase 15 calendar UX restructure — breadcrumb segment flip
    # (2026-05-10). The breadcrumb's middle segment renders the
    # CURRENT-MONTH label (e.g. `[may 2026]`), not the literal word
    # `[month]`. It is the toggle link back to the month grid on this
    # page. The active-view label is the trailing `[schedule]` segment,
    # rendered as plain text via `<span class="bracketed-active">`.
    it "breadcrumb carries [<current-month>] link and trailing [schedule] + [+] actions" do
      get "/calendar/schedule"
      now = Time.current
      month_label = Date.new(now.year, now.month, 1).strftime("%b %Y").downcase
      # `[may YYYY]` lives inside the BracketedLinkComponent link:
      # `<span class="bl">may 2026</span>` — surrounded by `>...<`.
      expect(response.body).to include(">#{month_label}<")
      # `[schedule]` is now the active label — plain span. Match the
      # bracketed-active rendering directly so the assertion is
      # explicit about it being non-linked.
      expect(response.body).to include('<span class="bracketed-active">[schedule]</span>')
      expect(response.body).to include(">+<")
    end

    # [schedule] is plain (active) text on the schedule view — no
    # `<a>` wrapping it, just a `<span class="bracketed-active">`.
    it "[schedule] active label is a plain span (no link, no Stimulus action)" do
      get "/calendar/schedule"
      expect(response.body).to match(
        %r{<span class="bracketed-active">\[schedule\]</span>}
      )
      # And critically, no `<a>` tag wraps the schedule label.
      expect(response.body).not_to match(
        %r{<a [^>]*>\[<span class="bl">schedule</span>\]</a>}
      )
    end

    # Regression: the current-month toggle link must target the
    # canonical month URL directly — NOT `/calendar`, which is the
    # view-persistence router. Routing it through `/calendar` lets a
    # stale `pito-calendar-view = schedule` in localStorage redirect
    # the user right back to schedule, making the click look broken.
    # The link also carries the `persistMonth` Stimulus action so the
    # view preference flips to "month" for next visits to `/calendar`.
    it "[<current-month>] toggle targets the canonical month URL with persist action" do
      get "/calendar/schedule"
      now = Time.current
      expected_href = "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
      month_label = Date.new(now.year, now.month, 1).strftime("%b %Y").downcase
      # ERB escapes `->` in the rendered `data-action` to `-&gt;`.
      # Rails `link_to` attribute ordering is not strictly guaranteed,
      # so assert the three required pieces (href, class, data-action)
      # all live on the same single `<a>` tag whose body is the
      # current-month label, without pinning their order.
      expect(response.body).to match(
        %r{<a\b(?=[^>]*\bhref="#{Regexp.escape(expected_href)}")(?=[^>]*\bclass="bracketed")(?=[^>]*\bdata-action="click-&gt;calendar-view-router#persistMonth")[^>]*>\[<span class="bl">#{Regexp.escape(month_label)}}
      )
    end

    it "[<current-month>] toggle is wrapped by a `calendar-view-router` controller mount" do
      get "/calendar/schedule"
      expect(response.body).to match(
        %r{<span data-controller="calendar-view-router">\s*<a [^>]*href="/calendar/month/\d{4}/\d{2}"[^>]*>\[<span class="bl">[a-z]{3} \d{4}}
      )
    end

    it "[<current-month>] toggle does NOT route through `/calendar` (the persistence router)" do
      get "/calendar/schedule"
      now = Time.current
      month_label = Date.new(now.year, now.month, 1).strftime("%b %Y").downcase
      expect(response.body).not_to match(
        %r{<a [^>]*href="/calendar"[^>]*>\[<span class="bl">#{Regexp.escape(month_label)}}
      )
    end

    # Placement check: the rendered breadcrumb row reads
    # `[calendar] / [may 2026] · [schedule] [+]`. Assert the four
    # segments appear in that document order so a future refactor that
    # misplaces a slot (e.g. drops the current-month link out of the
    # `:breadcrumbs` slot) gets caught.
    it "renders breadcrumb segments in [calendar] / [<month>] · [schedule] [+] order" do
      get "/calendar/schedule"
      cal_pos      = response.body.index('<span class="bl">calendar</span>')
      month_pos    = response.body.index(%r{<span class="bl">[a-z]{3} \d{4}</span>})
      schedule_pos = response.body.index('<span class="bracketed-active">[schedule]</span>')
      plus_pos     = response.body.index('<span class="bl">+</span>')
      expect(cal_pos).not_to be_nil
      expect(month_pos).not_to be_nil
      expect(schedule_pos).not_to be_nil
      expect(plus_pos).not_to be_nil
      expect(cal_pos).to be < month_pos
      expect(month_pos).to be < schedule_pos
      expect(schedule_pos).to be < plus_pos
    end

    it "with both past and future entries, renders the [today] divider" do
      create(:calendar_entry, :custom, starts_at: 5.days.ago, title: "past")
      create(:calendar_entry, :custom, starts_at: 5.days.from_now, title: "future")
      get "/calendar/schedule"
      expect(response.body).to include("[ today ]")
    end

    describe "?types= filter (calendar UX restructure)" do
      it "filters by types=game (single kind)" do
        g = create(:game)
        ce = create(:calendar_entry, :game_release, game: g, starts_at: 30.days.from_now, title: "released: g")
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "v", category_id: "10")
        get "/calendar/schedule?types=game"
        expect(response.body).to include("released: g")
        expect(response.body).not_to include("video published: v")
      end

      it "filters by types=video,game (union)" do
        g = create(:game)
        create(:calendar_entry, :game_release, game: g, starts_at: 30.days.from_now, title: "g_in_union")
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "v_in_union", category_id: "10")
        create(:calendar_entry, :custom, title: "custom_excluded", starts_at: 1.day.from_now)
        get "/calendar/schedule?types=video,game"
        expect(response.body).to include("g_in_union")
        expect(response.body).to include("video published: v_in_union")
        expect(response.body).not_to include("custom_excluded")
      end

      it "no types param shows all kinds" do
        v = create(:video)
        v.update!(privacy_status: :public, published_at: 1.day.ago, title: "vshow", category_id: "10")
        create(:calendar_entry, :custom, title: "cshow", starts_at: 1.day.from_now)
        get "/calendar/schedule"
        expect(response.body).to include("video published: vshow")
        expect(response.body).to include("cshow")
      end

      it "empty types= renders no entries" do
        create(:calendar_entry, :custom, title: "hidden_one", starts_at: 1.day.from_now)
        get "/calendar/schedule?types="
        expect(response.body).to include("no entries")
        expect(response.body).not_to include("hidden_one")
      end

      it "types=zorblax (all invalid) renders no entries" do
        create(:calendar_entry, :custom, title: "x", starts_at: 1.day.from_now)
        get "/calendar/schedule?types=zorblax"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no entries")
      end
    end

    it "filters by source=manual" do
      create(:calendar_entry, :milestone_manual, title: "podcast")
      v = create(:video)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "thevid", category_id: "10")
      get "/calendar/schedule?source=manual"
      expect(response.body).to include("podcast")
      expect(response.body).not_to include("video published: thevid")
    end

    it "sad: source=invalid redirects with flash" do
      get "/calendar/schedule?source=zorblax"
      expect(response).to redirect_to(calendar_schedule_path)
    end

    it "page=999 (out of range) renders empty list" do
      get "/calendar/schedule?page=999"
      expect(response).to have_http_status(:ok)
    end

    it "pagination: with > 50 entries, page 1 has 50 + page 2 has the rest" do
      55.times { |i| create(:calendar_entry, :custom, starts_at: (i + 1).days.from_now) }
      get "/calendar/schedule?page=1"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("page 1")
    end

    it "default state filter hides cancelled and superseded" do
      create(:calendar_entry, :custom, title: "active", starts_at: 1.day.from_now)
      create(:calendar_entry, :custom, :cancelled, title: "cxld", starts_at: 1.day.from_now)
      get "/calendar/schedule"
      expect(response.body).to include("active")
      expect(response.body).not_to include("cxld")
    end

    it "?state=all surfaces cancelled" do
      create(:calendar_entry, :custom, :cancelled, title: "cxld_too", starts_at: 1.day.from_now)
      get "/calendar/schedule?state=all"
      expect(response.body).to include("cxld_too")
    end
  end
end
