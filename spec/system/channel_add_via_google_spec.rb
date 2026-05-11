require "rails_helper"

# End-to-end happy path: `[+]` on /channels (or the Google banner on
# the same page) → OAuth runs with `prompt=select_account` → the
# callback enumerates `mine: true` channels and adds non-duplicates as
# Channel rows under the matching YoutubeConnection. Phase 24 moved
# the Google management surface onto /channels (banner on index + per-
# channel inline panel on show); the legacy `/settings/youtube` page is
# gone.
RSpec.describe "Add channels via Google", type: :system do
  let(:user) { User.first || create(:user) }
  let!(:connection) do
    create(:youtube_connection,
           user: user,
           email: "u@example.test",
           google_subject_id: "1099876543210123456789")
  end

  before do
    driven_by(:rack_test)

    OmniAuth.config.test_mode = true
    OmniAuth.config.failure_raise_out_environments = []
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "1099876543210123456789",
      info: { email: "u@example.test", name: "Sample User" },
      credentials: {
        token: "ya29.test-access-token",
        refresh_token: "1//test-refresh-token",
        expires_at: 1.hour.from_now.to_i
      },
      extra: { raw_info: {
        scope: [
          "openid", "email", "profile",
          "https://www.googleapis.com/auth/youtube.readonly",
          "https://www.googleapis.com/auth/yt-analytics.readonly",
          "https://www.googleapis.com/auth/youtube.force-ssl"
        ].join(" ")
      } }
    )
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  it "renders the Google banner on /channels with [+ add another Google account]" do
    visit channels_path
    expect(page).to have_button("[+ add another Google account]")
  end

  it "click [+ add another Google account] → OAuth → returns to /channels with the new channel linked" do
    allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
      items: [
        { id: "UCnewnewnewnewnewnewnewx",
          snippet: { title: "Fresh Channel" },
          statistics: { subscriber_count: 42 } }
      ],
      next_page_token: nil
    )

    visit channels_path
    expect(page).to have_button("[+ add another Google account]")

    expect {
      click_button "[+ add another Google account]"
    }.to change { Channel.where(youtube_connection_id: connection.id).count }.by(1)

    expect(page).to have_current_path(channels_path)
    expect(page).to have_content("Google account connected")
  end

  it "click [+ add another Google account] → OAuth → an already-linked channel is silently skipped" do
    Channel.create!(
      channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx",
      youtube_connection_id: connection.id,
      last_synced_at: 1.hour.ago
    )

    allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
      items: [
        { id: "UCdupdupdupdupdupdupdupx",
          snippet: { title: "Already Linked" } },
        { id: "UCfreshfreshfreshfreshfx",
          snippet: { title: "Fresh New" } }
      ],
      next_page_token: nil
    )

    visit channels_path
    expect {
      click_button "[+ add another Google account]"
    }.to change { Channel.count }.by(1)

    expect(page).to have_current_path(channels_path)
    expect(page).to have_content("already linked")

    expect(
      Channel.where(channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx").count
    ).to eq(1)
  end
end
