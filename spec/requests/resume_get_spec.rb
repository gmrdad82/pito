# frozen_string_literal: true

require "rails_helper"

# GET /resume re-renders the conversations sidebar (used to restore the
# panel after reload when localStorage says it was open).

RSpec.describe "GET /resume", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  describe "when authenticated" do
    before do
      authenticate_via_totp
      Conversation.create!
    end

    it "returns a turbo-stream targeting pito-sidebar" do
      get resume_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "lists conversation rows" do
      get resume_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.body).to include("data-conversation-uuid")
    end
  end

  describe "when anonymous" do
    it "does not render the sidebar (redirects away)" do
      get resume_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).not_to have_http_status(:ok)
    end
  end
end
