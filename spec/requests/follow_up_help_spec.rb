# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

# Request spec for the hashtag --help intercept in handle_follow_up.
# Tests that `#<handle> --help` and `#<handle> <action> --help` emit a
# synchronous system event rather than enqueuing FollowUpDispatchJob.
RSpec.describe "Follow-up --help intercept", type: :request do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.singleton }

  before do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed:)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
    conversation.turns.destroy_all
    Pito::FollowUp::Registry.register_all!
  end

  # A game_list event is a good public :append target with known actions.
  let(:source_turn) do
    conversation.turns.create!(input_kind: :slash, input_text: "/list games", position: 99)
  end

  let!(:source_event) do
    Event.create_with_position!(
      conversation:, turn: source_turn, kind: "system",
      payload: {
        "reply_handle" => "help-1234",
        "reply_target" => "game_list",
        "body"         => "games list"
      }
    )
  end

  # ── `#<handle> --help` → target page ──────────────────────────────────────

  context "#<handle> --help (target-level page)" do
    it "returns 204 No Content" do
      post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT enqueue FollowUpDispatchJob" do
      expect {
        post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      }.not_to have_enqueued_job(FollowUpDispatchJob)
    end

    it "creates a Turn for the echo" do
      expect {
        post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      }.to change(Turn, :count).by(1)
    end

    it "creates an echo event and a system event" do
      post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      turn = Turn.last
      kinds = turn.events.map(&:kind)
      expect(kinds).to include("echo")
      expect(kinds).to include("system")
    end

    it "system event body contains Usage:" do
      post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      turn        = Turn.last
      system_event = turn.events.find { |e| e.kind == "system" }
      expect(system_event).to be_present
      expect(system_event.payload["body"]).to include("Usage:")
    end

    it "system event is html (html: true)" do
      post "/chat", params: { input: "#help-1234 --help", uuid: conversation.uuid }
      turn         = Turn.last
      system_event = turn.events.find { |e| e.kind == "system" }
      expect(system_event.payload["html"]).to be(true)
    end
  end

  # ── `#<handle> <action> --help` → action page ─────────────────────────────

  context "#<handle> show --help (action-level page)" do
    it "returns 204 No Content" do
      post "/chat", params: { input: "#help-1234 show --help", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT enqueue FollowUpDispatchJob" do
      expect {
        post "/chat", params: { input: "#help-1234 show --help", uuid: conversation.uuid }
      }.not_to have_enqueued_job(FollowUpDispatchJob)
    end

    it "creates an echo + system event" do
      post "/chat", params: { input: "#help-1234 show --help", uuid: conversation.uuid }
      turn = Turn.last
      kinds = turn.events.map(&:kind)
      expect(kinds).to include("echo")
      expect(kinds).to include("system")
    end

    it "system event body contains action-specific help (id wording)" do
      post "/chat", params: { input: "#help-1234 show --help", uuid: conversation.uuid }
      turn         = Turn.last
      system_event = turn.events.find { |e| e.kind == "system" }
      expect(system_event.payload["body"]).to include("id")
    end
  end

  # ── Normal dispatch still works (no regression) ───────────────────────────

  context "normal #<handle> show 1 dispatch (no --help)" do
    it "enqueues FollowUpDispatchJob for a normal follow-up" do
      expect {
        post "/chat", params: { input: "#help-1234 show 1", uuid: conversation.uuid }
      }.to have_enqueued_job(FollowUpDispatchJob)
    end

    it "does NOT create a system event synchronously for a normal action" do
      # Normal append path creates echo + enqueues job (no synchronous system event)
      post "/chat", params: { input: "#help-1234 show 1", uuid: conversation.uuid }
      turn  = Turn.last
      kinds = turn.events.map(&:kind)
      expect(kinds).to include("echo")
      # System events are created by the job, not synchronously
      expect(kinds).not_to include("system")
    end
  end

  # ── HashtagHelp returns nil for internal target → fall through ─────────────

  context "when HashtagHelp returns nil (target has no copy or is unknown), normal dispatch runs" do
    let!(:unknown_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "unkn-9999",
          "reply_target" => "game_list",
          "body"         => "games"
        }
      )
    end

    before do
      # Stub HashtagHelp to return nil to simulate missing copy
      allow(Pito::MessageBuilder::HashtagHelp).to receive(:call).with(target: "game_list").and_return(nil)
    end

    it "falls through to normal dispatch when HashtagHelp returns nil" do
      expect {
        post "/chat", params: { input: "#unkn-9999 --help", uuid: conversation.uuid }
      }.to have_enqueued_job(FollowUpDispatchJob)
    end
  end
end
