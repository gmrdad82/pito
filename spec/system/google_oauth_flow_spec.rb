require "rails_helper"

# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). End-to-end happy path through the OmniAuth flow
# in test_mode. The system spec drives the connect button → Google
# (mocked) → callback → /settings/youtube round trip.
RSpec.describe "Google OAuth flow", type: :system do
  before do
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
        # Full pito scope set — happy path. The partial-grant branch
        # in `YoutubeConnections::OauthCallbacksController#create` is
        # covered in the request spec; here we just want the connect
        # → callback → /settings/youtube round-trip to complete cleanly.
        scope: [
          "openid", "email", "profile",
          "https://www.googleapis.com/auth/youtube.readonly",
          "https://www.googleapis.com/auth/yt-analytics.readonly",
          "https://www.googleapis.com/auth/youtube.force-ssl"
        ].join(" ")
      } }
    )

    driven_by(:rack_test)

    # The OAuth callback enumerates `mine: true` channels under the
    # just-authorized connection and adds non-duplicates as Channel
    # rows. Stub the client to return an empty list so the spec
    # doesn't depend on a live YouTube response (and so WebMock
    # doesn't reject the request) — both connect rounds in this spec
    # produce zero new Channel rows, which is fine; this spec asserts
    # on the YoutubeConnection upsert, not channel discovery.
    allow_any_instance_of(Youtube::Client).to receive(:channels_list)
      .and_return(items: [], next_page_token: nil)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  it "lets the user connect their Google account from settings → youtube" do
    visit settings_youtube_path
    expect(page).to have_content("no Google account connected")

    expect {
      click_button "[connect]"
    }.to change { YoutubeConnection.unscoped.count }.by(1)

    expect(page).to have_current_path(settings_youtube_path)
  end

  # Multi-connection (2026-05-10). After the first account connects,
  # the page shows a `[+ connect another Google account]` button that
  # initiates a SECOND OmniAuth round. The mocked auth hash is reused
  # under a different google_subject_id, so the callback creates a
  # second YoutubeConnection row alongside the first.
  it "lets the user connect a SECOND Google account from settings → youtube" do
    user = User.first || create(:user)
    create(:youtube_connection,
           user: user,
           email: "first-account@example.test",
           google_subject_id: "first-account-subject-aaaaaaaa")

    # The OmniAuth mock represents the SECOND Google account — the
    # uid differs so the callback creates a new row.
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "second-account-subject-bbbbbbbb",
      info: { email: "second-account@example.test", name: "Second User" },
      credentials: {
        token: "ya29.second-account-token",
        refresh_token: "1//second-account-refresh",
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

    visit settings_youtube_path
    expect(page).to have_content("first-account@example.test")
    expect(page).to have_button("[+ connect another Google account]")

    expect {
      click_button "[+ connect another Google account]"
    }.to change { YoutubeConnection.unscoped.where(user_id: user.id).count }.by(1)

    expect(page).to have_current_path(settings_youtube_path)
    # Both rows now live side-by-side; the page surfaces both emails.
    expect(page).to have_content("first-account@example.test")
    expect(page).to have_content("second-account@example.test")
  end
end
