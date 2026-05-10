require "rails_helper"

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

  it "renders the empty state when no notifications" do
    render
    expect(rendered).to include("no notifications yet.")
  end

  it "renders the [ all ] / [ unread ] filter cluster" do
    render
    # `all` is the active filter — renders as bracketed-active text.
    # `unread` is the inactive filter — renders as a link with a
    # bracketed `<span class="bl">unread</span>` inner. We match on the
    # presence of both labels inside the dot-list.
    expect(rendered).to include('class="bracketed bracketed-active">[ all ]</span>')
    expect(rendered).to match(/<a class="bracketed" href="\/notifications\?filter=unread">\[<span class="bl">unread<\/span>\]<\/a>/)
  end

  it "marks the active filter as bracketed-active" do
    assign(:filter, "unread")
    render
    expect(rendered).to match(/<span class="bracketed bracketed-active">\[\s*unread\s*\]<\/span>/)
  end

  it "shows the [ mark all read ] button when unread_count > 0" do
    assign(:notifications, [ build_stubbed(:notification, :video_published) ])
    assign(:unread_count, 1)
    render
    expect(rendered).to include("mark all read")
  end

  it "hides the [ mark all read ] button when unread_count == 0" do
    render
    expect(rendered).not_to include("mark all read")
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
