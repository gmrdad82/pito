# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Video visit consume endpoint", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  let(:conversation) { Conversation.singleton }
  let!(:video) { create(:video, title: "My Vid", youtube_video_id: "yt_xyz") }

  # video_visit's tools.yml `consume` entry lands in a later task — stub the
  # Matrix seam so the handler's `declared?("consume")` resolves without it
  # (the same fake-target pattern T8.4 established; see
  # spec/requests/follow_up_spec.rb).
  before do
    allow(Pito::Dispatch::Matrix).to receive(:actions_for).and_call_original
    allow(Pito::Dispatch::Matrix).to receive(:actions_for).with("video_visit").and_return([ "consume" ])
    allow(Pito::Dispatch::Matrix).to receive(:mode_for).and_call_original
    allow(Pito::Dispatch::Matrix).to receive(:mode_for).with("video_visit").and_return(:mutate)
  end

  # Build a persisted, :visiting video-visit event (as the follow-up handler does).
  def visiting_event
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :hashtag,
      input_text: "#abc visit My Vid"
    )
    Event.create_with_position!(
      conversation:, turn:, kind: "system",
      payload: Pito::MessageBuilder::Video::Visit.call(video, conversation: conversation)
    )
  end

  describe "POST /videos/visit_consume — unauthenticated" do
    # JSON-format requests get an explicit 401 (Sessions::AuthConcern) — the
    # redirect-to-root auth wall is a browser affordance.
    it "rejects with 401 JSON (auth required, no allow_anonymous)" do
      post video_visit_consume_path, params: { event_id: visiting_event.id }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
    end
  end

  context "when authenticated" do
    before { login! }

    it "flips the event to the visited follow-up state" do
      event = visiting_event
      post video_visit_consume_path, params: { event_id: event.id }, as: :json

      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.kind).to eq("system_follow_up")
      expect(event.payload["visit_state"]).to eq("visited")
      expect(event.payload["body"]).not_to include("pito-network-shimmer")
    end

    it "is idempotent — a second consume leaves it visited" do
      event = visiting_event
      post video_visit_consume_path, params: { event_id: event.id }, as: :json
      post video_visit_consume_path, params: { event_id: event.id }, as: :json

      expect(response).to have_http_status(:ok)
      event.reload
      expect(event.kind).to eq("system_follow_up")
      expect(event.payload["visit_state"]).to eq("visited")
    end
  end
end
