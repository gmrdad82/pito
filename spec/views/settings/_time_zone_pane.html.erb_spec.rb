require "rails_helper"

# Beta 4 — Phase F3-DEEP-A (2026-05-20). Time-zone pane TUI revamp.
#
# The pane renders a single dropdown over every `ActiveSupport::TimeZone`
# entry + every IANA-only zone. The TUI revamp:
#
#   * lowered the H2 to lowercase ("time zone")
#   * added a terse muted `saved: <IANA>` row above the select
#   * styled the dropdown via the global form-input rule (dark-bg
#     hairline border, monospace 13px, no border-radius)
#   * rendered the [update] submit as a bracketed-link button
#
# The view reads `Current.user&.time_zone` to seed the dropdown's
# selected option. The pane is rendered inline on /settings (no
# standalone page).
RSpec.describe "settings/_time_zone_pane.html.erb", type: :view do
  let(:user) { build_stubbed(:user, time_zone: "Europe/Bucharest") }

  before do
    allow(Current).to receive(:user).and_return(user)
    render partial: "settings/time_zone_pane"
  end

  describe "lowercase heading" do
    it "renders the H2 heading as lowercase `time zone`" do
      expect(rendered).to include("<h2>time zone</h2>")
    end
  end

  describe "muted saved-zone row" do
    it "renders the saved IANA zone in a muted text row" do
      # The pane echoes the current user's saved zone above the
      # dropdown so the user can compare what's stored vs. what
      # they're about to pick.
      expect(rendered).to match(/text-muted[^"]*"[^>]*>saved: Europe\/Bucharest/)
    end

    it "renders the saved-zone row with tabular-nums for alignment" do
      expect(rendered).to include("tabular-nums")
    end
  end

  describe "dropdown" do
    it "renders the time-zone <select> with name=`time_zone`" do
      expect(rendered).to have_css('select[name="time_zone"]')
    end

    it "carries the form-label above the dropdown" do
      expect(rendered).to have_css('label[for="settings_time_zone"]', text: "your time zone")
    end

    it "renders two optgroups (common Rails subset + full IANA tail)" do
      expect(rendered).to have_css('optgroup[label="common"]')
      expect(rendered).to have_css('optgroup[label="all IANA"]')
    end

    it "marks the user's saved zone as selected" do
      expect(rendered).to match(/<option value="Europe\/Bucharest" selected/)
    end

    it "renders Pacific/Kiritimati (UTC+14 edge zone) in the IANA-only optgroup" do
      # Rails subset of `ActiveSupport::TimeZone.all` may or may not
      # carry every edge zone; the full IANA optgroup must cover the
      # tail.
      expect(rendered).to include("Pacific/Kiritimati")
    end

    it "submits the form to /settings/time_zone via PATCH" do
      expect(rendered).to include('action="/settings/time_zone"')
      # Rails form_with method override for PATCH renders a hidden
      # `_method=patch` input alongside the POST attribute on the form.
      expect(rendered).to match(/name="_method"[^>]*value="patch"/)
    end
  end

  describe "[update] bracketed submit" do
    it "renders the submit button with the bracketed class + .bl label span" do
      expect(rendered).to have_css(
        'button[type="submit"].bracketed span.bl', text: "update"
      )
    end
  end

  describe "tz hint copy" do
    it "renders the form hint below the dropdown" do
      expect(rendered).to include("affects how every time is rendered across pito.")
    end
  end

  describe "Etc/UTC default for users without a saved zone" do
    let(:nil_zone_user) { build_stubbed(:user, time_zone: nil) }
    before do
      allow(Current).to receive(:user).and_return(nil_zone_user)
      render partial: "settings/time_zone_pane"
    end

    it "falls back to Etc/UTC for the muted saved row" do
      expect(rendered).to include("saved: Etc/UTC")
    end
  end

  describe "no forbidden JS confirm hooks" do
    it "does NOT render data-turbo-confirm" do
      expect(rendered).not_to include("data-turbo-confirm")
    end
  end
end
