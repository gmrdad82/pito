require "rails_helper"

# Verification sweep (2026-05-10) — focused coverage for the
# `calendar/month/_navigation` partial's prev/today/next alignment.
#
# Existing `calendar/month_spec.rb` asserts each link renders, but does
# NOT lock the layout contract: the nav row uses
# `class="calendar-nav-row"` with `display: flex; justify-content:
# space-between` so `[prev]` anchors left, optional `[today]` floats
# centered, and `[next]` anchors right. When the user is already on the
# current month, `[today]` is suppressed and an empty `<span
# aria-hidden>` placeholder keeps the flex distribution working.
#
# Locking these properties here means a future refactor that drops the
# class or changes the alignment surface gets caught by request-level
# coverage.
RSpec.describe "Calendar month navigation alignment", type: :request do
  describe "GET /calendar/month/:year/:month" do
    it "wraps prev/today/next in a `.calendar-nav-row` container" do
      get "/calendar/month/2026/05"
      expect(response.body).to include('class="calendar-nav-row"')
    end

    it "uses flex space-between alignment on the nav row" do
      get "/calendar/month/2026/05"
      expect(response.body).to match(
        /<div class="calendar-nav-row"[^>]*style="[^"]*justify-content:\s*space-between/
      )
    end

    it "renders [prev] before [next] in document order" do
      get "/calendar/month/2026/05"
      prev_pos = response.body.index('<span class="bl">prev</span>')
      next_pos = response.body.index('<span class="bl">next</span>')
      expect(prev_pos).not_to be_nil
      expect(next_pos).not_to be_nil
      expect(prev_pos).to be < next_pos
    end

    # Pick a month that is provably NOT the current one regardless of
    # when the suite runs — a year far in the past has no risk of
    # colliding with `Time.current`'s month.
    context "when not on the current month" do
      let(:non_current_path) { "/calendar/month/2020/01" }

      it "renders a [today] link between [prev] and [next]" do
        get non_current_path
        prev_pos  = response.body.index('<span class="bl">prev</span>')
        today_pos = response.body.index('<span class="bl">today</span>')
        next_pos  = response.body.index('<span class="bl">next</span>')
        expect(today_pos).not_to be_nil
        expect(prev_pos).to be < today_pos
        expect(today_pos).to be < next_pos
      end

      it "[today] href targets the calendar root (router)" do
        get non_current_path
        expect(response.body).to match(
          %r{href="/calendar"[^>]*>\[<span class="bl">today</span>\]}
        )
      end
    end

    context "when on the current month" do
      it "suppresses [today] and renders an empty placeholder span" do
        now = Time.current
        get "/calendar/month/#{now.year}/#{format('%02d', now.month)}"
        expect(response.body).not_to match(/<span class="bl">today<\/span>/)
        # The placeholder lives inside `.calendar-nav-row` — assert at
        # least one `aria-hidden` empty span sits inside the row.
        expect(response.body).to match(
          /<div class="calendar-nav-row"[^>]*>(?:.|\n)*?<span aria-hidden="true">\s*<\/span>/
        )
      end
    end
  end
end
