# frozen_string_literal: true

# spec/services/pito/auth/session_cookie_spec.rb
#
# Contract: Pito::Auth::SessionCookie
#   .mint!(request, totp_verified_at:) — writes an encrypted cookie; returns SessionData
#   .from_request(request)             — reads + validates the cookie; nil if missing/expired
#   #touch!(data)                      — refreshes last_seen_at (debounced)
#   #clear!                            — deletes the cookie
#   #mark_totp_verified!(data, at:)    — bumps totp_verified_at and last_seen_at
#
# SessionData#expired? — true when last_seen_at is older than IDLE_TIMEOUT (24h).
#
# We exercise encrypt/decrypt and expiry using real integration sessions so that
# ActionDispatch::CookieJar encryption uses the actual app key.

require "rails_helper"

RSpec.describe Pito::Auth::SessionCookie, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:seed)         { ROTP::Base32.random_base32 }
  let(:totp)         { ROTP::TOTP.new(seed) }
  let(:conversation) { Conversation.singleton }

  # Helper: log in via HTTP so the integration session holds a real encrypted cookie.
  def login!
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{totp.now}", uuid: conversation.uuid }
  end

  # ── Mint + round-trip ────────────────────────────────────────────────────────

  describe "mint and read round-trip" do
    it "sets the encrypted cookie after a successful login" do
      login!
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_present
    end

    it "cookie sets Current.session — subsequent /chat commands are dispatched as authenticated" do
      login!
      # After login the session cookie is set. A POST /chat with an unknown
      # command returns 204 No Content (the job is enqueued) rather than
      # redirecting to root (which happens when unauthenticated).
      conversation.turns.destroy_all
      expect {
        post "/chat", params: { input: "/help", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(authenticated: true))
    end
  end

  # ── Idle-timeout expiry ──────────────────────────────────────────────────────

  describe "idle timeout (SessionData#expired?)" do
    it "is not expired when last_seen_at is recent" do
      data = Pito::Auth::SessionCookie::SessionData.new(
        sid: SecureRandom.uuid,
        authenticated: true,
        totp_verified_at: Time.current,
        created_at: Time.current,
        last_seen_at: Time.current
      )
      expect(data.expired?).to be false
    end

    it "is expired when last_seen_at is older than IDLE_TIMEOUT" do
      data = Pito::Auth::SessionCookie::SessionData.new(
        sid: SecureRandom.uuid,
        authenticated: true,
        totp_verified_at: 25.hours.ago,
        created_at: 25.hours.ago,
        last_seen_at: 25.hours.ago
      )
      expect(data.expired?).to be true
    end

    it "is expired when last_seen_at is nil" do
      data = Pito::Auth::SessionCookie::SessionData.new(
        sid: SecureRandom.uuid,
        authenticated: true,
        totp_verified_at: nil,
        created_at: Time.current,
        last_seen_at: nil
      )
      expect(data.expired?).to be true
    end

    it "redirects to root when the cookie has idled past IDLE_TIMEOUT" do
      login!

      # Travel past the idle timeout so the cookie reads as expired.
      travel_to(Pito::Auth::SessionCookie::IDLE_TIMEOUT.from_now + 1.second) do
        # /notifications requires auth → expect redirect when cookie expired.
        get notifications_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  # ── Logout (clear!) ──────────────────────────────────────────────────────────

  describe "#clear!" do
    it "deletes the cookie on DELETE /logout" do
      login!
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_present
      delete "/logout"
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_blank
    end
  end

  # ── Garbage / tampered cookie ────────────────────────────────────────────────

  describe "tampered or nil token" do
    it "treats a garbage cookie value as absent — auth-required request redirects to root" do
      # Inject a raw junk value directly into the cookie store.
      # The encrypted reader will raise InvalidMessage, which #read rescues → nil.
      # With no valid session, an auth-required action must redirect to root.
      cookies[Pito::Auth::SessionCookie::COOKIE_NAME] = "not_a_real_encrypted_value"
      get notifications_path
      expect(response).to redirect_to(root_path)
    end
  end
end
