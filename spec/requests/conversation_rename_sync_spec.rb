# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# P54 — PATCH /chat/:uuid (rename) broadcasts conversation_row to pito:global
# so every open sidebar on other instances updates without a reload.

RSpec.describe "PATCH /chat/:uuid — global cable sync on rename", type: :request do
  include ActionCable::TestHelper

  let!(:conversation) { create(:conversation, title: "Original Title") }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "broadcasts a conversation_row replace to pito:global after rename" do
      expect {
        patch conversation_path(uuid: conversation.uuid),
              params:  { title: "Renamed Chat" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('action="replace"')
        expect(html).to include("conversation_row_#{conversation.uuid}")
      }
    end

    it "includes the new title in the global broadcast" do
      expect {
        patch conversation_path(uuid: conversation.uuid),
              params:  { title: "Renamed Chat" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include("Renamed Chat")
      }
    end

    it "broadcasts the chatbox conversation-name slot to the conversation's own stream" do
      expect {
        patch conversation_path(uuid: conversation.uuid),
              params:  { title: "Renamed Chat" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('action="replace"')
        expect(html).to include("pito-chatbox-conversation-name")
        expect(html).to include("Renamed Chat")
      }
    end

    it "does NOT broadcast to pito:global when the title is blank (422 path)" do
      expect {
        patch conversation_path(uuid: conversation.uuid),
              params:  { title: "" },
              headers: { "Accept" => "application/json" }
      }.not_to have_broadcasted_to("pito:global")
    end

    it "does NOT broadcast to pito:global on the draft-save path" do
      expect {
        patch conversation_path(uuid: conversation.uuid),
              params:  { draft: "work in progress" },
              headers: { "Accept" => "application/json" }
      }.not_to have_broadcasted_to("pito:global")
    end
  end
end
