# frozen_string_literal: true

# spec/services/pito/auth/chat_login_spec.rb
#
# Contract: Pito::Auth::ChatLogin.call(code:, request:)
#   → Result with status: :ok + session_data   — valid code, not throttled
#   → Result with status: :invalid             — wrong code, not throttled
#   → Result with status: :throttled           — IP has exhausted the limit
#
# Per-IP throttle: SessionThrottle::LIMIT (10) failures per 5-minute window.

require "rails_helper"

RSpec.describe Pito::Auth::ChatLogin do
  let(:seed)    { ROTP::Base32.random_base32 }
  let(:totp)    { ROTP::TOTP.new(seed) }
  let(:ip)      { "1.2.3.4" }
  let(:request) { instance_double("ActionDispatch::Request", remote_ip: ip, cookie_jar: cookie_jar) }
  let(:cookie_jar) { instance_double("ActionDispatch::Cookies::CookieJar").as_null_object }

  before { AppSetting.enroll_totp!(seed: seed) }

  # Stub SessionCookie.mint! so we don't need a real cookie jar for unit tests.
  before do
    allow(Pito::Auth::SessionCookie).to receive(:mint!).and_return(
      Pito::Auth::SessionCookie::SessionData.new(
        sid: "test-sid",
        authenticated: true,
        totp_verified_at: Time.current,
        created_at: Time.current,
        last_seen_at: Time.current
      )
    )
  end

  after do
    # Clear the throttle bucket so tests don't bleed state.
    Rails.cache.delete_matched("pito:login_failed:*")
  end

  describe ".call" do
    context "with a valid code and no throttle" do
      it "returns status :ok" do
        result = described_class.call(code: totp.now, request: request)
        expect(result.status).to eq(:ok)
      end

      it "returns an authenticated? Result" do
        result = described_class.call(code: totp.now, request: request)
        expect(result.authenticated?).to be true
      end

      it "populates session_data" do
        result = described_class.call(code: totp.now, request: request)
        expect(result.session_data).to be_present
      end

      it "calls SessionCookie.mint!" do
        described_class.call(code: totp.now, request: request)
        expect(Pito::Auth::SessionCookie).to have_received(:mint!)
      end
    end

    context "with a wrong code and no throttle" do
      it "returns status :invalid" do
        result = described_class.call(code: "000000", request: request)
        expect(result.status).to eq(:invalid)
      end

      it "session_data is nil" do
        result = described_class.call(code: "000000", request: request)
        expect(result.session_data).to be_nil
      end

      it "is not authenticated?" do
        result = described_class.call(code: "000000", request: request)
        expect(result.authenticated?).to be false
      end

      it "records a failure in the throttle bucket" do
        allow(SessionThrottle).to receive(:record_failure).and_call_original
        described_class.call(code: "000000", request: request)
        expect(SessionThrottle).to have_received(:record_failure).with(ip)
      end
    end

    context "when throttle is exhausted" do
      before do
        allow(SessionThrottle).to receive(:exhausted?).with(ip).and_return(true)
      end

      it "returns status :throttled without verifying the code" do
        expect(Pito::Auth::TotpVerifier).not_to receive(:call)
        result = described_class.call(code: totp.now, request: request)
        expect(result.status).to eq(:throttled)
      end

      it "does not mint a session" do
        described_class.call(code: totp.now, request: request)
        expect(Pito::Auth::SessionCookie).not_to have_received(:mint!)
      end
    end

    context "incremental throttle build-up" do
      it "does not throttle after fewer than LIMIT failures" do
        # Record LIMIT - 1 failures, then a fresh (wrong) call should still be :invalid.
        (SessionThrottle::LIMIT - 1).times do
          described_class.call(code: "000000", request: request)
        end
        result = described_class.call(code: "000000", request: request)
        # At exactly LIMIT the call WILL be throttled on the next attempt
        # (LIMIT failures incremented; next call reads LIMIT >= LIMIT).
        # Verify the LIMIT-th call is the last :invalid one (not throttled yet
        # because the throttle check runs BEFORE incrementing).
        expect(result.status).to eq(:invalid)
      end
    end
  end
end
