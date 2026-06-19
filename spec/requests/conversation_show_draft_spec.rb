# frozen_string_literal: true

require "rails_helper"

# Draft restore + scoping specs for ConversationsController#show,
# the start screen (/), and the 404 page.

RSpec.describe "Conversation show draft restore and scoping", type: :request do
  describe "GET /chat/:uuid — draft restore" do
    let(:conversation) { create(:conversation, draft: "my saved draft") }

    it "renders the draft value in the textarea" do
      # The draft is only exposed to an authenticated session (security).
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)
      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }

      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("my saved draft")
    end

    it "wires the pito--draft Stimulus controller on #pito-chatbox" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("pito--draft")
    end

    it "includes the conversation uuid as pito--draft-uuid-value" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include(%(data-pito--draft-uuid-value="#{conversation.uuid}"))
    end

    context "when there is no draft" do
      let(:conversation) { create(:conversation, draft: nil) }

      it "renders an empty textarea value" do
        get conversation_path(uuid: conversation.uuid)
        # The textarea value attribute should be empty (not contain stale draft text).
        expect(response.body).to include("pito--draft")
      end
    end
  end

  describe "GET / — start screen" do
    it "does NOT include the pito--draft controller" do
      get root_path
      expect(response.body).not_to include("pito--draft")
    end

    it "does NOT include a pito--draft-uuid-value attribute" do
      get root_path
      expect(response.body).not_to include("pito--draft-uuid-value")
    end
  end

  describe "GET /some-unknown-url — 404 page" do
    it "does NOT include the pito--draft controller" do
      get "/some-totally-unknown-url-xyz"
      expect(response.body).not_to include("pito--draft")
    end

    it "does NOT include a pito--draft-uuid-value attribute" do
      get "/some-totally-unknown-url-xyz"
      expect(response.body).not_to include("pito--draft-uuid-value")
    end
  end
end
