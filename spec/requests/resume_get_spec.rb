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
  describe "pagination (?after=)" do
    it "appends the next page's rows and replaces the sentinel" do
      stub_const("Conversation::SIDEBAR_PAGE_SIZE", 2)
      3.times { Conversation.create! }
      authenticate_via_totp

      get resume_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      cursor = response.body[/after=([A-Za-z0-9_\-]+)/, 1]
      expect(cursor).to be_present

      get resume_path(after: cursor), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="append" target="pito-conversations-more"')
      expect(response.body).to include(Pito::ListPager::SentinelComponent::SENTINEL_ID)
    end
  end
end
