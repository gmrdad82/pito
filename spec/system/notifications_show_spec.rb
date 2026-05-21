require "rails_helper"

RSpec.describe "Notifications show", type: :system do
  before { driven_by(:rack_test) }

  let(:notification) { create(:notification, :video_published) }

  it "renders the formatter-derived title" do
    payload = Pito::Notifications::Formatter::InApp.payload_for(notification)
    visit "/notifications/#{notification.id}"
    expect(page).to have_selector("h1", text: payload[:title])
  end

  it "renders the [ back ] link" do
    visit "/notifications/#{notification.id}"
    expect(page).to have_link("back", href: notifications_path)
  end

  it "renders the per-channel delivery state" do
    visit "/notifications/#{notification.id}"
    expect(page).to have_content("in_app: yes")
    expect(page.body).to match(/discord:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
    expect(page.body).to match(/slack:\s+(pending|disabled|\d{4}-\d{2}-\d{2})/)
  end

  it "renders [ mark read ] when unread" do
    visit "/notifications/#{notification.id}"
    expect(page).to have_button("[mark read]")
  end

  it "click [ mark read ] flips the row to read" do
    visit "/notifications/#{notification.id}"
    click_button("[mark read]")
    expect(notification.reload.in_app_read_at).to be_present
  end

  it "renders [ mark unread ] when read" do
    notification.mark_read!
    visit "/notifications/#{notification.id}"
    expect(page).to have_button("[mark unread]")
  end

  it "click [ mark unread ] clears the read stamp" do
    notification.mark_read!
    visit "/notifications/#{notification.id}"
    click_button("[mark unread]")
    expect(notification.reload.in_app_read_at).to be_nil
  end

  it "renders [ open ] when url is present" do
    notification.update!(url: "https://example.com/abc")
    visit "/notifications/#{notification.id}"
    expect(page).to have_link("open")
  end

  it "omits [ open ] when url is blank" do
    notification.update!(url: nil)
    visit "/notifications/#{notification.id}"
    expect(page).not_to have_link("open")
  end

  it "renders last_error when non-blank" do
    notification.update!(last_error: "HTTP 502 from discord")
    visit "/notifications/#{notification.id}"
    expect(page).to have_content("HTTP 502 from discord")
  end

  it "[ open ] link wires the notification-link Stimulus controller" do
    notification.update!(url: "https://example.com/x")
    visit "/notifications/#{notification.id}"
    open_link = find_link("open")
    expect(open_link["data-controller"]).to include("notification-link")
    expect(open_link["data-action"]).to include("notification-link#markReadAndNavigate")
  end

  it "does NOT include `data-turbo-confirm` anywhere on the detail page" do
    visit "/notifications/#{notification.id}"
    expect(page.body).not_to include("data-turbo-confirm")
  end

  it "escapes user-supplied url (no html_safe leak)" do
    # The model rejects URLs that aren't absolute http(s) or app-paths,
    # so we can't actually create a malicious row. Verify that the
    # rendered href matches the stored value byte-for-byte (ERB
    # auto-escape). This guards against a future regression where the
    # view changes to use html_safe / raw / sanitize on the URL.
    notification.update!(url: "https://example.com/x?q=a&b=c")
    visit "/notifications/#{notification.id}"
    expect(page.body).to include("https://example.com/x?q=a&amp;b=c")
  end
end
