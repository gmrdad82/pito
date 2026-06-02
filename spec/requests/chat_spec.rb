# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe "Chat requests", type: :request do
  include ActionCable::TestHelper

  describe "POST /chat" do
    let(:conversation) { Conversation.singleton }

    # Log in via /login <code> so subsequent requests are authenticated.
    # Clear the auth-round-trip turns so per-test counts start clean.
    before do
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)
      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
      conversation.turns.destroy_all
    end

    context "with a slash command" do
      let(:params) { { input: "/help", uuid: conversation.uuid } }

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
        expect(turn.events.map(&:kind)).to include("echo")
        expect(turn.events.count).to be >= 2
      end

      it "creates the Turn with the correct attributes" do
        post "/chat", params: params
        turn = Turn.last
        expect(turn.input_kind).to eq("slash")
        expect(turn.input_text).to eq("/help")
        expect(turn.conversation).to eq(conversation)
      end

      it "stamps started_at on the turn" do
        post "/chat", params: params
        expect(Turn.last.started_at).not_to be_nil
      end

      it "stamps completed_at after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        expect(Turn.last.completed_at).not_to be_nil
      end

      it "broadcasts echo to the conversation stream immediately" do
        stream = "pito:conversation:#{conversation.uuid}"
        expect { post "/chat", params: params }.to have_broadcasted_to(stream).at_least(:once)
      end

      it "broadcasts result events after the job runs" do
        stream = "pito:conversation:#{conversation.uuid}"
        count = 0
        perform_enqueued_jobs do
          expect { post "/chat", params: params }
            .to have_broadcasted_to(stream).at_least(:once)
        end
      end
    end

    context "with the confirm_demo command" do
      let(:params) { { input: "/confirm_demo", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates a confirmation Event after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        confirm_event = turn.events.find { |e| e.kind == "confirmation" }
        expect(confirm_event).to be_present
        expect(confirm_event.payload["prompt_key"]).to eq("pito.slash.confirm_demo.prompt")
        expect(confirm_event.payload["command_text"]).to eq("/confirm_demo")
      end
    end

    context "with an unknown verb" do
      let(:params) { { input: "/nope", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates an error Event with the unknown_verb message_key after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        error_event = turn.events.find { |e| e.kind == "error" }
        expect(error_event).to be_present
        expect(error_event.payload["message_key"]).to eq("pito.slash.errors.unknown_verb")
      end
    end

    context "with a non-slash input (unknown word)" do
      let(:params) { { input: "hello", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one Turn" do
        expect { post "/chat", params: params }.to change(Turn, :count).by(1)
      end

      it "creates echo + thinking + error Events after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        expect(turn.events.map(&:kind)).to include("echo", "thinking", "error")
        error_event = turn.events.find { |e| e.kind == "error" }
        expect(error_event.payload["message_key"]).to eq("pito.chat.errors.unknown_input")
      end

      it "broadcasts echo to the conversation stream immediately" do
        stream = "pito:conversation:#{conversation.uuid}"
        expect { post "/chat", params: params }.to have_broadcasted_to(stream).at_least(:once)
      end
    end

    context "with a recognised chat verb (list)" do
      let(:params) { { input: "list videos", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one new Turn" do
        expect { post "/chat", params: params }.to change(Turn, :count).by(1)
      end

      it "creates echo + system Events after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        expect(turn.events.map(&:kind)).to include("echo", "system")
        expect(turn.events.count).to be >= 2
      end

      it "result events include elapsed_seconds in payload" do
        perform_enqueued_jobs { post "/chat", params: params }
        result_event = Turn.last.events.find { |e| e.kind != "echo" }
        expect(result_event.payload["elapsed_seconds"]).not_to be_nil
      end
    end

    context "channel + period context" do
      let(:params) { { input: "/help", uuid: conversation.uuid, channel: "@gaming", period: "7d" } }

      it "enqueues the job with the channel parameter" do
        expect {
          post "/chat", params: params
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: "@gaming"))
      end

      it "defaults channel to @all when not provided" do
        expect {
          post "/chat", params: { input: "/help", uuid: conversation.uuid }
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: "@all"))
      end
    end

    context "with refinement input (open turn exists)" do
      before do
        # Create a recent turn so the parser classifies input as :refinement
        conversation.turns.create!(
          input_text: "list videos",
          input_kind: :chat,
          position: 1,
          created_at: 5.minutes.ago
        )
      end

      let(:params) { { input: "add ctr", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates a new Turn (async path always creates a turn for the echo)" do
        expect { post "/chat", params: params }.to change(Turn, :count).by(1)
      end

      it "persists the echo immediately" do
        post "/chat", params: params
        expect(Turn.last.events.map(&:kind)).to include("echo")
      end

      it "produces result events after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        kinds = Turn.last.events.map(&:kind)
        expect(kinds).to include("echo")
        expect(kinds.count).to be >= 2
      end
    end

    context "with a garbled slash input (no verb)" do
      let(:params) { { input: "/", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates an error Event with the parse_failed message_key after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        error_event = turn.events.find { |e| e.kind == "error" }
        expect(error_event).to be_present
        expect(error_event.payload["message_key"]).to eq("pito.slash.errors.parse_failed")
      end
    end

    context "with an empty input and existing uuid" do
      it "returns 204 No Content" do
        post "/chat", params: { input: "", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end

      it "does not create a Turn or Event" do
        expect {
          post "/chat", params: { input: "", uuid: conversation.uuid }
        }.not_to change(Turn, :count)

        expect {
          post "/chat", params: { input: "", uuid: conversation.uuid }
        }.not_to change(Event, :count)
      end
    end

    context "with blank input and no uuid (home→chat transition step 1)" do
      it "creates a conversation and returns uuid + signed_stream_name as JSON" do
        post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body["uuid"]).to be_present
        expect(body["signed_stream_name"]).to be_present
      end

      it "persists a new Conversation" do
        expect {
          post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        }.to change(Conversation, :count).by(1)
      end

      it "does not create any Turn or Event" do
        expect {
          post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        }.not_to change(Event, :count)
      end

      it "returns a uuid that resolves to GET /chat/:uuid" do
        post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        uuid = response.parsed_body["uuid"]
        get conversation_path(uuid:)
        expect(response).to have_http_status(:ok)
      end
    end

    context "home→chat transition sequence (server side)" do
      it "step 1 then step 2 creates events on the conversation" do
        post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        uuid = response.parsed_body["uuid"]

        perform_enqueued_jobs do
          expect {
            post "/chat", params: { uuid:, input: "/help" }
          }.to change(Event, :count).by_at_least(1)
        end

        expect(response).to have_http_status(:no_content)
      end

      it "events from step 2 belong to the conversation created in step 1" do
        post "/chat", params: { input: "" }, headers: { "Accept" => "application/json" }
        uuid = response.parsed_body["uuid"]
        perform_enqueued_jobs { post "/chat", params: { uuid:, input: "/help" } }
        expect(Conversation.find_by!(uuid:).events).not_to be_empty
      end
    end

    context "without a uuid (first message from start screen via HTML)" do
      let(:params) { { input: "/help" } }

      it "redirects to /chat/:uuid" do
        post "/chat", params: params
        expect(response).to redirect_to(%r{/chat/[a-f0-9\-]+\z})
        uuid = URI.parse(response.headers["Location"]).path.split("/").last
        expect(Conversation.find_by(uuid:)).to be_present
      end

      it "creates a new Conversation" do
        expect { post "/chat", params: params }.to change(Conversation, :count).by(1)
      end

      it "creates a Turn on the new conversation" do
        perform_enqueued_jobs { post "/chat", params: params }
        uuid = URI.parse(response.headers["Location"]).path.split("/").last
        conv = Conversation.find_by!(uuid:)
        expect(conv.turns.count).to eq(1)
        expect(conv.turns.first.input_text).to eq("/help")
      end
    end
  end
end
