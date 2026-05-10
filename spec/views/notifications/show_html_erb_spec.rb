require "rails_helper"

RSpec.describe "notifications/show.html.erb", type: :view do
  let(:notification) { create(:notification, :video_published) }
  let(:payload) { NotificationFormatter::InApp.payload_for(notification) }

  before do
    assign(:notification, notification)
    assign(:payload, payload)
  end

  it "renders the formatter-derived title" do
    render
    # The detail page renders `@payload[:title]` (from the per-kind
    # template), NOT the raw `notification.title` column. Assert on
    # the payload's actual title — that's the user-facing string.
    expect(rendered).to include(payload[:title])
  end

  it "renders [back]" do
    render
    expect(rendered).to match(/\[<span class="bl">back<\/span>\]/)
  end

  it "wires the modal-close Stimulus action on [back]" do
    render
    # `>` gets HTML-entity encoded inside attribute values.
    expect(rendered).to include("notification-modal#close")
  end

  it "wraps the body in the notification_detail_frame Turbo Frame" do
    render
    expect(rendered).to include('id="notification_detail_frame"')
  end

  it "renders [ mark read ] when unread" do
    render
    expect(rendered).to include("mark read")
    expect(rendered).not_to include("mark unread")
  end

  it "renders [ mark unread ] when read" do
    notification.mark_read!
    assign(:notification, notification.reload)
    render
    expect(rendered).to include("mark unread")
  end

  it "renders per-channel delivery state" do
    render
    expect(rendered).to include("in_app: yes")
    expect(rendered).to match(/discord:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
    expect(rendered).to match(/slack:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
  end

  it "renders [open] when url is present" do
    notification.update!(url: "https://example.com/x")
    render
    expect(rendered).to match(/\[<span class="bl">open<\/span>\]/)
  end

  it "omits [open] when url is blank" do
    notification.update!(url: nil)
    render
    expect(rendered).not_to match(/\[<span class="bl">open<\/span>\]/)
  end

  it "shows last_error when non-blank" do
    notification.update!(last_error: "boom: HTTP 502")
    render
    expect(rendered).to include("boom: HTTP 502")
  end

  it "wires the notification-link Stimulus controller on [open]" do
    notification.update!(url: "https://example.com/x")
    render
    expect(rendered).to include('data-controller="notification-link"')
    expect(rendered).to include("notification-link#markReadAndNavigate")
  end

  it "does NOT contain `data-turbo-confirm`" do
    render
    expect(rendered).not_to include("data-turbo-confirm")
  end

  it "does NOT contain `window.confirm`" do
    render
    expect(rendered).not_to include("window.confirm")
  end

  it "uses default ERB escaping on the user-facing url (no html_safe)" do
    notification.update!(url: "https://example.com/x?q=a&b=c")
    render
    expect(rendered).to include("https://example.com/x?q=a&amp;b=c")
  end
end
