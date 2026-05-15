require "rails_helper"

# Phase 7.5 §11g — thin system spec for the channel change history
# view. Walks the headline journey: open `/channels/:slug` → click
# `[changes]` → land on `/channels/:slug/history` → see the row.
RSpec.describe "Channel change history journey", type: :system do
  before do
    driven_by(:rack_test)
    ChannelSync.clear
  end

  let(:user) { Current.user || @auto_signed_in_user || User.first || create(:user) }
  let!(:channel) do
    create(:channel,
           title: "Pito Channel",
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv")
  end

  it "lets the user click [changes] from the show page and see the rows" do
    create(:channel_change_log,
           channel: channel,
           changed_by_user: user,
           field: "title",
           old_value: "Old test title",
           new_value: "New test title",
           changed_at: 2.hours.ago)

    visit channel_path(channel)
    expect(page).to have_link(text: /\[\s*changes\s*\]/)

    click_link("[changes]")

    expect(page.current_path).to eq(channel_change_logs_path(channel))
    expect(page).to have_selector("h1", text: /change history/)
    expect(page).to have_content("Old test title")
    expect(page).to have_content("New test title")
    expect(page).to have_content(user.username)
  end

  it "renders the empty state when no changes exist" do
    visit channel_change_logs_path(channel)
    expect(page).to have_content("no changes yet")
  end

  it "renders XSS payloads as literal text (escaped)" do
    create(:channel_change_log,
           channel: channel,
           changed_by_user: user,
           field: "title",
           old_value: "<script>alert('x')</script>",
           new_value: "Clean",
           changed_at: 1.hour.ago)

    visit channel_change_logs_path(channel)
    # The literal text appears in the visible page body.
    expect(page).to have_content("<script>alert('x')</script>")
    # And no real <script> tag is rendered (rack_test exposes the raw
    # HTML, which still contains the escaped string but not the
    # un-escaped form).
    expect(page.html).not_to include("<script>alert('x')</script>")
  end
end
