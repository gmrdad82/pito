# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Logout via /logout", type: :request do
  let(:conversation) { Conversation.singleton }
  let!(:seed) { ROTP::Base32.random_base32 }
  let(:totp) { ROTP::TOTP.new(seed) }

  before { AppSetting.enroll_totp!(seed: seed) }

  def last_turn_events
    Turn.last_for(conversation).events.order(:position)
  end

  def login!
    post "/chat", params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.turns.destroy_all
  end

  describe "/logout slash command" do
    it "clears the session cookie synchronously" do
      login!
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_present

      post "/chat", params: { input: "/logout", uuid: conversation.uuid }

      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_blank
    end

    it "emits an echo (with triggers_logout) then a system event" do
      login!
      post "/chat", params: { input: "/logout", uuid: conversation.uuid }

      kinds = last_turn_events.pluck(:kind)
      expect(kinds).to include("echo", "system")
      echo = last_turn_events.find { |e| e.kind == "echo" }
      expect(echo.payload["text"]).to eq("/logout")
      expect(echo.payload["triggers_logout"]).to be(true)
    end

    it "system event payload carries a logout text from the dictionary" do
      login!
      post "/chat", params: { input: "/logout", uuid: conversation.uuid }

      system_event = last_turn_events.find { |e| e.kind == "system" }
      expect(I18n.t("pito.copy.auth.logouts")).to include(system_event.payload["text"])
    end

    it "works even when already unauthenticated (idempotent cookie clear)" do
      post "/chat", params: { input: "/logout", uuid: conversation.uuid }

      kinds = last_turn_events.pluck(:kind)
      expect(kinds).to include("echo", "system")
    end
  end

  describe "DELETE /logout (HTTP route)" do
    it "clears the session cookie and redirects to root" do
      login!
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_present

      delete "/logout"
      expect(response).to redirect_to(root_path)
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_blank
    end
  end
end
