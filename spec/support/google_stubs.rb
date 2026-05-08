# Phase 7 — Test fixture strategy (decision 7.16, dispatched
# 2026-05-07).
#
# WebMock stubs based on Google's published response shapes.
#
# The user has not yet exercised the OAuth flow with their real
# Google account, so VCR cassettes cannot be recorded against
# live Google traffic. These stubs let the spec suite exercise
# the full client / refresher / disconnect surfaces against
# canned response shapes that match Google's documented JSON.
#
# VCR cassettes recorded against the user's real Google account
# will replace these in a follow-up cassette-recording session
# post-Phase-7-implementation. That session is the gate before
# Phase 8 (Data Sync).
#
# Sensitive-data filters (when cassettes land):
#   - bearer tokens (Authorization: Bearer ya29.…)
#   - refresh tokens (request bodies of oauth2.googleapis.com/token)
#   - client_secret form bodies
#   - public API keys (key= query params)
module GoogleStubs
  TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
  REVOKE_ENDPOINT = "https://oauth2.googleapis.com/revoke"
  YOUTUBE_DATA = "https://youtube.googleapis.com/youtube/v3"
  YOUTUBE_ANALYTICS = "https://youtubeanalytics.googleapis.com/v2"

  module_function

  # Canned 200 response from the OAuth token-refresh endpoint.
  def stub_refresh_success(access_token: "test-access-token-refreshed",
                           refresh_token: nil,
                           expires_in: 3600)
    body = { "access_token" => access_token, "expires_in" => expires_in,
             "scope" => "openid email profile",
             "token_type" => "Bearer" }
    body["refresh_token"] = refresh_token if refresh_token
    WebMock.stub_request(:post, TOKEN_ENDPOINT)
      .to_return(status: 200, body: body.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # Canned 400 response with error: "invalid_grant" — the refresh
  # token has been revoked or expired.
  def stub_refresh_invalid_grant
    WebMock.stub_request(:post, TOKEN_ENDPOINT)
      .to_return(
        status: 400,
        body: { error: "invalid_grant",
                error_description: "Token has been expired or revoked." }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # Canned 200 response from the OAuth revocation endpoint.
  def stub_revoke_success
    WebMock.stub_request(:post, REVOKE_ENDPOINT)
      .to_return(status: 200, body: "")
  end

  # Canned 400 response with body shape "invalid_token" — used by
  # the already-revoked idempotent path in 7C.
  def stub_revoke_already_revoked
    WebMock.stub_request(:post, REVOKE_ENDPOINT)
      .to_return(
        status: 400,
        body: { error: "invalid_token",
                error_description: "Token expired or revoked" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
