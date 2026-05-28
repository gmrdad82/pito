# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe "Chat requests", type: :request do
  include ActionCable::TestHelper

  describe "POST /chat" do
    let(:conversation) { Conversation.singleton }

    context "with a slash command" do
      let(:params) { { input: "/help" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one Turn" do
        expect {
          post "/chat", params: params
        }.to change(Turn, :count).by(1)
      end

      it "creates an echo Event and a response Event" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.events.count).to eq(2)
        expect(turn.events.pluck(:kind)).to contain_exactly("echo", "error")
      end

      it "creates the Turn with the correct attributes" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.input_kind).to eq("slash")
        expect(turn.input_text).to eq("/help")
        expect(turn.conversation).to eq(conversation)
      end

      it "broadcasts to the conversation stream" do
        stream = "pito:conversation:#{conversation.id}"
        expect {
          post "/chat", params: params
        }.to have_broadcasted_to(stream).at_least(:once)
      end
    end

    context "with a non-slash input" do
      let(:params) { { input: "hello" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one Turn" do
        expect {
          post "/chat", params: params
        }.to change(Turn, :count).by(1)
      end

      it "creates only an echo Event (no response)" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.events.count).to eq(1)
        expect(turn.events.pluck(:kind)).to contain_exactly("echo")
      end

      it "broadcasts to the conversation stream" do
        stream = "pito:conversation:#{conversation.id}"
        expect {
          post "/chat", params: params
        }.to have_broadcasted_to(stream).at_least(:once)
      end
    end

    context "with an empty input" do
      let(:params) { { input: "" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
