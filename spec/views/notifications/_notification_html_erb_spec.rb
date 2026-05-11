require "rails_helper"

# 2026-05-10 — Notification row partial. The first column is a
# bulk-select checkbox rendered for EVERY row (read AND unread). The
# row also renders the per-event-type glyph (color emoji) and the
# severity badge — those are independent dimensions (glyph =
# event_type, badge = severity), so neither is redundant with the
# other.
RSpec.describe "notifications/_notification.html.erb", type: :view do
  let(:unread) { create(:notification, :video_published) }
  let(:read)   { create(:notification, :read, :video_published) }

  it "renders a checkbox for an unread row" do
    render partial: "notifications/notification", locals: { notification: unread }
    expect(rendered).to match(/input[^>]*type="checkbox"[^>]*data-bulk-select-target="checkbox"/)
  end

  it "renders a checkbox for a READ row (always-on column)" do
    render partial: "notifications/notification", locals: { notification: read }
    expect(rendered).to match(/input[^>]*type="checkbox"[^>]*data-bulk-select-target="checkbox"/)
  end

  it "renders the event-type glyph (color emoji)" do
    render partial: "notifications/notification", locals: { notification: unread }
    expected_emoji = NotificationFormatter::EVENT_TYPE_EMOJI.fetch("video_published")
    expect(rendered).to include('class="notification-glyph"')
    expect(rendered).to include(expected_emoji)
  end

  it "renders the severity badge with the severity text" do
    render partial: "notifications/notification", locals: { notification: unread }
    # `:video_published` defaults to severity `:info`. The badge
    # renders the literal severity word inside a colored bordered box
    # via the shared `StatusBadgeComponent` — `.status-badge` is the
    # canonical class, with a per-kind `--<kind>` modifier.
    expect(rendered).to include("status-badge--info")
    expect(rendered).to match(/<span class="status-badge status-badge--info">info<\/span>/)
  end

  it "carries the dom_id on the row" do
    render partial: "notifications/notification", locals: { notification: unread }
    expect(rendered).to include(%(id="#{ActionView::RecordIdentifier.dom_id(unread)}"))
  end

  it "marks the row with the unread/read class" do
    render partial: "notifications/notification", locals: { notification: unread }
    expect(rendered).to include("notification-unread")

    render partial: "notifications/notification", locals: { notification: read }
    expect(rendered).to include("notification-read")
  end

  it "value attribute on the checkbox is the notification id" do
    render partial: "notifications/notification", locals: { notification: unread }
    expect(rendered).to include(%(value="#{unread.id}"))
  end
end
