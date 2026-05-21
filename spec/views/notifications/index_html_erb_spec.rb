require "rails_helper"

# Phase 16 §3 UX restructure 2026-05-10:
#   - `[ all ]` / `[ unread ]` bracketed-link toggles -> `[ ] unread`
#     FilterChipComponent.
#   - Per-row `[ mark read ]` action removed.
#   - Notification detail opens in an in-page modal (Turbo Frame inside
#     a `<dialog>` mounted on the index).
#   - Caption under the H1 explains the cleanup behaviour.
RSpec.describe "notifications/index.html.erb", type: :view do
  before do
    assign(:notifications, [])
    assign(:unread_count, 0)
    assign(:has_failures, false)
    assign(:filter, "all")
    assign(:kind, nil)
    assign(:severity, nil)
    assign(:page, 1)
    assign(:total_pages, 1)
  end

  it "renders the heading" do
    render
    expect(rendered).to include("notifications")
  end

  it "renders the cleanup caption under the heading" do
    render
    expect(rendered).to include("notifications are deleted 7 days after being read.")
  end

  # 2026-05-10 — glyph legend at the modal top. The legend maps every
  # event-type emoji (📺, 🎮, 🚨…) to a human label so the otherwise
  # opaque pictograph in the row's first column is readable. The
  # legend is built from `Pito::Notifications::Formatter::EVENT_TYPE_EMOJI`
  # at render time, so a new kind landing in the map appears here
  # automatically (no separate copy to maintain).
  describe "glyph legend" do
    it "renders the legend container with the documented class" do
      render
      expect(rendered).to include("notification-glyph-legend")
    end

    it "renders every emoji from EVENT_TYPE_EMOJI" do
      render
      Pito::Notifications::Formatter::EVENT_TYPE_EMOJI.each_value do |emoji|
        expect(rendered).to include(emoji)
      end
    end

    it "renders a humanized label for each event_type (underscores -> spaces)" do
      render
      Pito::Notifications::Formatter::EVENT_TYPE_EMOJI.each_key do |kind|
        expect(rendered).to include(kind.tr("_", " "))
      end
    end
  end

  it "renders the empty state when no notifications" do
    render
    expect(rendered).to include("no notifications yet.")
  end

  it "renders the [ ] unread filter chip" do
    render
    expect(rendered).to match(/<a[^>]*class="filter-chip"[^>]*>.*\[\s*\].*unread/m)
  end

  it "renders [x] when filter=unread is active" do
    assign(:filter, "unread")
    # FilterChipComponent reads from `request.query_parameters` for its
    # `checked?` calculation -- push the param onto the test request.
    controller.request.query_parameters[:filter] = "unread"
    render
    expect(rendered).to include("[x]")
  end

  it "shows the [ mark all as read ] button when unread_count > 0" do
    assign(:notifications, [ build_stubbed(:notification, :video_published) ])
    assign(:unread_count, 1)
    render
    expect(rendered).to include("mark all as read")
  end

  it "hides the [ mark all as read ] button when unread_count == 0" do
    render
    expect(rendered).not_to include("mark all as read")
  end

  it "wires the dynamic-button Stimulus controller on the wrapper" do
    assign(:notifications, [ build_stubbed(:notification, :video_published) ])
    assign(:unread_count, 1)
    render
    expect(rendered).to include('data-controller="bulk-select notifications-dynamic-button"')
    expect(rendered).to include('data-notifications-dynamic-button-mark-all-url-value="/notifications/mark_all_read"')
    expect(rendered).to include('data-notifications-dynamic-button-mark-read-url-value="/notifications/mark_read"')
    expect(rendered).to include('data-notifications-dynamic-button-total-unread-value="1"')
  end

  it "renders the notification-detail modal mount" do
    render
    expect(rendered).to include('data-controller="notification-modal"')
    expect(rendered).to include('data-notification-modal-target="dialog"')
    expect(rendered).to include('id="notification_detail_frame"')
  end

  it "shows the webhook misconfigured banner when @has_failures is true" do
    assign(:has_failures, true)
    render
    expect(rendered).to include("webhook delivery failing — see notification detail.")
  end

  it "hides the banner when @has_failures is false" do
    render
    expect(rendered).not_to include("webhook delivery failing")
  end
end
