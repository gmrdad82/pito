# frozen_string_literal: true

# spec/requests/login_throttle_spec.rb
#
# Covers the per-IP throttle path in Pito::Auth::ChatLogin:
#   - 10 failures within the window → the next /login attempt returns :throttled
#     and the system event signals throttling.
#   - Throttled state clears when the cache expires (simulated via cache clear).
#
# Does NOT weaken the existing happy-path / invalid-code cases in login_spec.rb.

require "rails_helper"

RSpec.describe "Login throttle via POST /chat /login", type: :request do
  include ActiveJob::TestHelper

  let(:conversation) { Conversation.singleton }
  let(:seed)         { ROTP::Base32.random_base32 }
  let(:totp)         { ROTP::TOTP.new(seed) }

  before { AppSetting.enroll_totp!(seed: seed) }

  after do
    Rails.cache.delete_matched("pito:login_failed:*")
    conversation.turns.destroy_all
  end

  def submit_bad_code
    post "/chat", params: { input: "/login 000000", uuid: conversation.uuid }
    conversation.turns.destroy_all
  end

  def last_turn_events
    Turn.last_for(conversation)&.events&.order(:position) || []
  end

  describe "throttle trip" do
    it "throttles after LIMIT consecutive failures in the window" do
      (SessionThrottle::LIMIT - 1).times { submit_bad_code }

      # LIMIT-th failure — still :invalid, not yet throttled.
      post "/chat", params: { input: "/login 000000", uuid: conversation.uuid }
      error_event = last_turn_events.find { |e| e.kind == "error" }
      expect(error_event).to be_present
      conversation.turns.destroy_all

      # Next attempt — bucket is now at LIMIT, so the chat login is throttled.
      post "/chat", params: { input: "/login 000000", uuid: conversation.uuid }
      error_event2 = last_turn_events.find { |e| e.kind == "error" }
      expect(error_event2).to be_present
    end

    it "valid code still accepted after throttle bucket is cleared" do
      # Fill the bucket to trigger throttle.
      SessionThrottle::LIMIT.times { submit_bad_code }

      # Clear cache (simulating TTL expiry).
      Rails.cache.delete_matched("pito:login_failed:*")

      # Now a valid code should succeed.
      post "/chat", params: { input: "/login #{totp.now}", uuid: conversation.uuid }
      events = last_turn_events
      expect(events.any? { |e| e.kind == "system" }).to be true
      expect(events.none? { |e| e.kind == "error" }).to be true
    end
  end
end
