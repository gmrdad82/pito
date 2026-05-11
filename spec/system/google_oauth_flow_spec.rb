require "rails_helper"

# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). End-to-end happy path through the OmniAuth flow
# in test_mode. The system spec drives the connect button → Google
# (mocked) → callback → /channels round trip (Phase 24 moved the
# return target from /settings/youtube to /channels).
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
        # → callback → /channels round-trip to complete cleanly.
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
    # doesn't reject the request).
    allow_any_instance_of(Youtube::Client).to receive(:channels_list)
      .and_return(items: [], next_page_token: nil)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  it "lets the user connect their Google account from the /channels [+] button" do
    visit channels_path
    # Banner is dropped — the empty-state "no Google account connected"
    # copy is gone too. The `[+]` button next to the heading is the
    # single entry point.
    expect(page).to have_content("no channels yet")

    expect {
      click_button "[+]"
    }.to change { YoutubeConnection.unscoped.count }.by(1)

    expect(page).to have_current_path(channels_path)
  end

  # Multi-connection: with one connection already present, clicking
  # `[+]` initiates a SECOND OmniAuth round. The mocked auth hash is
  # reused under a different google_subject_id, so the callback
  # creates a second YoutubeConnection row alongside the first.
  it "lets the user connect a SECOND Google account from /channels via [+]" do
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

    visit channels_path
    # Banner is dropped — the connection's email is no longer surfaced
    # on the /channels index. The `[+]` heading button stays as the
    # single entry point and still POSTs with `account=new`.
    expect(page).not_to have_content("first-account@example.test")
    expect(page).to have_button("[+]")

    expect {
      click_button "[+]"
    }.to change { YoutubeConnection.unscoped.where(user_id: user.id).count }.by(1)

    expect(page).to have_current_path(channels_path)
    # The second connection row exists in the DB; neither email
    # surfaces on /channels anymore (banner gone).
    expect(YoutubeConnection.unscoped.where(user_id: user.id).pluck(:email)).to contain_exactly(
      "first-account@example.test",
      "second-account@example.test"
    )
  end
end
