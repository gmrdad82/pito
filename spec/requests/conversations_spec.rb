# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation requests", type: :request do
  describe "GET /chat/:uuid" do
    let(:conversation) { create(:conversation) }

    it "renders the conversation page for a known uuid" do
      get conversation_path(uuid: conversation.uuid)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(conversation.uuid)
    end

    it "returns 404 for an unknown uuid" do
      get conversation_path(uuid: "nonexistent-uuid-1234")
      expect(response).to have_http_status(:not_found)
    end

    it "subscribes to the correct Turbo Stream" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("<turbo-cable-stream-source")
    end

    it "renders the scrollback container" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include('id="pito-scrollback"')
    end

    it "includes the uuid in the chat form" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include(conversation.uuid)
    end
  end
end
