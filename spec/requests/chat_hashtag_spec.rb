# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe "Chat requests", type: :request do
  include ActionCable::TestHelper

  describe "POST /chat" do
    let(:conversation) { Conversation.singleton }

    before do
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)
      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
      conversation.turns.destroy_all
    end

    context "with a hashtag message" do
      before do
        conf_turn = conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 99)
        Event.create_with_position!(
          conversation:, turn: conf_turn,
          kind: "confirmation",
          payload: {
            command: "test",
            confirmation_handle: "alpha-1234",
            authenticated: true
          }
        )
      end

      let(:params) { { input: "#alpha-1234 hello", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one Turn" do
        expect { post "/chat", params: params }.to change(Turn, :count).by(1)
      end

      it "persists the echo Event immediately (before job runs)" do
        post "/chat", params: params
        expect(Turn.last.events.map(&:kind)).to include("echo")
      end

      it "enqueues a ChatDispatchJob" do
        expect { post "/chat", params: params }.to have_enqueued_job(ChatDispatchJob)
      end

      it "creates result Events after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        expect(turn.events.map(&:kind)).to include("echo", "system")
        expect(turn.events.count).to be >= 2
      end

      it "creates the Turn with the correct attributes" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.input_kind).to eq("hashtag")
        expect(turn.input_text).to eq("#alpha-1234 hello")
        expect(turn.conversation).to eq(conversation)
      end

      it "does not forward channel/period to the job" do
        expect {
          post "/chat", params: { input: "#alpha-1234 hello", uuid: conversation.uuid, channel: "@gaming", period: "7d" }
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: nil, period: nil))
      end

      it "routes #<handle> confirm to hashtag when the event has no reply_handle (unknown handle)" do
        # Events created via the old confirmation_handle path (no reply_handle) are
        # not routable by the follow-up engine, so they fall through to hashtag routing.
        expect {
          post "/chat", params: { input: "#alpha-1234 confirm", uuid: conversation.uuid }
        }.to change(Turn, :count).by(1)
      end
    end
  end
end
