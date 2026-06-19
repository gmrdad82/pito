# frozen_string_literal: true

require "rails_helper"

# ChatController#create clears the conversation draft when a message is sent.

RSpec.describe "ChatController draft clearing", type: :request do
  let!(:conversation) { create(:conversation, draft: "saved text") }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post chat_path, params: { input: "/login #{ROTP::TOTP.new(seed).now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  it "clears the draft when a chat message is sent" do
    expect(conversation.reload.draft).to eq("saved text")

    post chat_path, params: { input: "hello world", uuid: conversation.uuid }

    expect(conversation.reload.draft).to be_nil
  end

  it "clears the draft when a slash command is sent" do
    post chat_path, params: { input: "/help", uuid: conversation.uuid }

    expect(conversation.reload.draft).to be_nil
  end

  it "does not fail when there is no draft to clear" do
    conversation.update!(draft: nil)

    expect {
      post chat_path, params: { input: "hello", uuid: conversation.uuid }
    }.not_to raise_error

    expect(response).to have_http_status(:no_content)
  end
end
