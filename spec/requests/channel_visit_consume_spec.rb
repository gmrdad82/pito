# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Channel visit consume endpoint", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  let(:conversation) { Conversation.singleton }
  let!(:channel) { create(:channel, handle: "@gaming", youtube_channel_id: "UCxyz") }

  # Build a persisted, :visiting channel-visit event (as the follow-up handler does).
  def visiting_event
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :hashtag,
      input_text: "#abc visit @gaming"
    )
    Event.create_with_position!(
      conversation:, turn:, kind: "system",
      payload: Pito::MessageBuilder::Channel::Visit.call(channel, conversation: conversation)
    )
  end

  describe "POST /channels/visit_consume — unauthenticated" do
    it "redirects to root (auth required, no allow_anonymous)" do
      post channel_visit_consume_path, params: { event_id: visiting_event.id }, as: :json
      expect(response).to redirect_to(root_path)
    end
  end

  context "when authenticated" do
    before { login! }

    it "flips the event to the visited follow-up state" do
      event = visiting_event
      post channel_visit_consume_path, params: { event_id: event.id }, as: :json

      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.kind).to eq("system_follow_up")
      expect(event.payload["visit_state"]).to eq("visited")
      expect(event.payload["body"]).not_to include("pito-network-shimmer")
    end

    it "is idempotent — a second consume leaves it visited" do
      event = visiting_event
      post channel_visit_consume_path, params: { event_id: event.id }, as: :json
      post channel_visit_consume_path, params: { event_id: event.id }, as: :json

      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.kind).to eq("system_follow_up")
      expect(event.payload["visit_state"]).to eq("visited")
    end
  end
end
