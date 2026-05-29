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

      it "creates an echo Event and response Events" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.events.first.kind).to eq("echo")
        expect(turn.events.count).to be >= 2
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

    context "with the confirm_demo command" do
      let(:params) { { input: "/confirm_demo" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates a confirmation_prompt Event with the right payload" do
        post "/chat", params: params
        turn = Turn.last
        confirm_event = turn.events.find { |e| e.kind == "confirmation_prompt" }
        expect(confirm_event).to be_present
        expect(confirm_event.payload["prompt_key"]).to eq("pito.slash.confirm_demo.prompt")
        expect(confirm_event.payload["command_text"]).to eq("/confirm_demo")
      end
    end

    context "with an unknown verb" do
      let(:params) { { input: "/nope" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates an error Event with the unknown_verb message_key" do
        post "/chat", params: params
        turn = Turn.last
        error_event = turn.events.find { |e| e.kind == "error" }
        expect(error_event).to be_present
        expect(error_event.payload["message_key"]).to eq("pito.slash.errors.unknown_verb")
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

    context "with a garbled slash input (no verb)" do
      let(:params) { { input: "/" } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates an error Event with the parse_failed message_key" do
        post "/chat", params: params
        turn = Turn.last
        error_event = turn.events.find { |e| e.kind == "error" }
        expect(error_event).to be_present
        expect(error_event.payload["message_key"]).to eq("pito.slash.errors.parse_failed")
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
