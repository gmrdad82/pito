require "rails_helper"

# End-to-end happy path: `[+]` on /channels → land on the Google
# connection manage page → click `[add]` → OAuth runs with
# `prompt=select_account` → the callback enumerates `mine: true`
# channels and adds non-duplicates as Channel rows under the
# matching YoutubeConnection.
#
# This is the critical user journey post-redesign (2026-05-10). The
# legacy "select channels to add" multi-select form is gone — the
# `[add]` button is the new (and only) entry point.
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

  it "routes [+] on /channels to /settings/youtube and renders the `channels` heading" do
    visit channels_path
    click_link "[+]"
    expect(page).to have_current_path(settings_youtube_path)
    expect(page).to have_content("Google connection")
    # New heading per the 2026-05-10 redesign — was "linked channels".
    expect(page).to have_content("channels")
  end

  it "click [add] → OAuth → returns to /settings/youtube with the new channel linked" do
    # The OAuth dance landing on the callback enumerates `mine: true`.
    # Stub the client so the callback adds one brand-new channel.
    allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
      items: [
        { id: "UCnewnewnewnewnewnewnewx",
          snippet: { title: "Fresh Channel" },
          statistics: { subscriber_count: 42 } }
      ],
      next_page_token: nil
    )

    visit settings_youtube_path
    expect(page).to have_button("[add]")

    expect {
      click_button "[add]"
    }.to change { Channel.where(youtube_connection_id: connection.id).count }.by(1)

    expect(page).to have_current_path(settings_youtube_path)
    expect(page).to have_content("Google account connected")
    expect(page).to have_content("Fresh Channel")
  end

  it "click [add] → OAuth → an already-linked channel is silently skipped (no duplicate, no crash)" do
    # Pre-existing channel — pito already knows about it.
    Channel.create!(
      channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx",
      youtube_connection_id: connection.id,
      last_synced_at: 1.hour.ago
    )

    # OAuth callback's `mine: true` returns both the duplicate AND a
    # brand-new channel. The duplicate must be silent-skipped; the
    # new one must be added.
    allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
      items: [
        { id: "UCdupdupdupdupdupdupdupx",
          snippet: { title: "Already Linked" } },
        { id: "UCfreshfreshfreshfreshfx",
          snippet: { title: "Fresh New" } }
      ],
      next_page_token: nil
    )

    visit settings_youtube_path
    expect {
      click_button "[add]"
    }.to change { Channel.count }.by(1)

    expect(page).to have_current_path(settings_youtube_path)
    expect(page).to have_content("Fresh New")
    expect(page).to have_content("already linked")

    # No duplicate rows for the existing UC id.
    expect(
      Channel.where(channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx").count
    ).to eq(1)
  end
end
