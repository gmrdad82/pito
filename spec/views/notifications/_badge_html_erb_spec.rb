require "rails_helper"

RSpec.describe "notifications/_badge.html.erb", type: :view do
  it "renders an empty wrapper when unread_count is 0" do
    render partial: "notifications/badge", locals: { unread_count: 0 }
    expect(rendered).to include('id="notifications_badge"')
    expect(rendered).not_to match(/\[\s*\d+\s*\]/)
  end

  it "renders [ N ] when unread_count > 0" do
    render partial: "notifications/badge", locals: { unread_count: 3 }
    expect(rendered).to match(/\[\s*3\s*\]/)
  end

  it "carries the stable dom_id `notifications_badge`" do
    render partial: "notifications/badge", locals: { unread_count: 5 }
    expect(rendered).to include('id="notifications_badge"')
  end

  it "renders an aria-label for assistive tech" do
    render partial: "notifications/badge", locals: { unread_count: 5 }
    expect(rendered).to include('aria-label="5 unread notifications"')
  end

  it "treats nil count defensively (falsy → no [ N ])" do
    render partial: "notifications/badge", locals: { unread_count: nil }
    expect(rendered).not_to match(/\[\s*\d+\s*\]/)
  end
end
