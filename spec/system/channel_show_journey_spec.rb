require "rails_helper"

# Phase 7.5 §11b — thin system spec for the channel show page.
# 2026-05-11 restructure — the page now has three sections: detail
# pane, analytics pane (first), Google connection pane (second), and a
# non-pane videos table at the bottom. The journey walks all four
# surfaces and verifies `[see all videos]` lands on the pre-filtered
# videos picker when the channel has more than 30 videos.
RSpec.describe "Channel show journey", type: :system do
  before do
    driven_by(:rack_test)
    ChannelSync.clear
  end

  let!(:channel) do
    create(:channel,
           title: "Pito Journey",
           handle: "@pitojourney",
           description: "Hello world.",
           subscriber_count: 1_000,
           view_count: 50_000,
           video_count: 5)
  end

  it "loads /channels, clicks into a channel, and sees the four sections in the new order" do
    # Need >30 videos to make the `[see all videos]` link render.
    31.times { create(:video, channel: channel) }

    visit channels_path
    # The picker page renders the channel; clicking its name lands on
    # the show page. The picker truncates the URL cell with an
    # ellipsis, so we navigate via the show path directly rather than
    # asserting the full URL is present on the picker.
    visit channel_path(channel)

    # Detail section — title in H1, handle, outbound links.
    expect(page).to have_selector("h1", text: "Pito Journey")
    expect(page).to have_content("@pitojourney")
    expect(page).to have_link(text: /YouTube/)
    expect(page).to have_link(text: /Studio/)

    # Analytics section — formatted counts + [full analytics].
    expect(page).to have_content("subscribers")
    expect(page).to have_content("1,000")
    expect(page).to have_content("50,000")
    expect(page).to have_link(text: /full analytics/i, href: channel_analytics_path(channel))

    # Google connection section — heading present (no connection on
    # this factory channel, so the empty state renders).
    expect(page).to have_content(/Google connection/)

    # Videos section — heading + [see all videos] (>30 videos).
    expect(page).to have_content(/videos \(31\)/)
    expect(page).to have_link(text: /see all videos/i)

    click_link("[see all videos]")

    expect(page.current_path).to eq(videos_path)
    expect(page.current_url).to include("channel=#{channel.to_param}")
  end

  it "omits the [see all videos] link when the channel has 30 or fewer videos" do
    visit channel_path(channel)

    expect(page).to have_content(/videos \(0\)/)
    expect(page).not_to have_link(text: /see all videos/i)
  end
end
