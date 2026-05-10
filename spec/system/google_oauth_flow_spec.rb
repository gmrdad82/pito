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
        scope: "openid email profile https://www.googleapis.com/auth/youtube.readonly"
      } }
    )

    driven_by(:rack_test)

    # The redirect-back from the callback lands on /settings/youtube,
    # which calls `Youtube::Client#channels_list(mine: true)`. Stub
    # the client so the spec does not depend on a live YouTube
    # response (and so WebMock doesn't reject the request).
    allow_any_instance_of(Youtube::Client).to receive(:channels_list)
      .and_return(items: [], next_page_token: nil)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  it "lets the user connect their Google account from settings → youtube" do
    visit settings_youtube_path
    expect(page).to have_content("no google account connected")

    expect {
      click_button "[ connect ]"
    }.to change { YoutubeConnection.unscoped.count }.by(1)

    expect(page).to have_current_path(settings_youtube_path)
  end
end
