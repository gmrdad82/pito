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

    context "with a non-slash input pito can't parse (witty reply)" do
      let(:params) { { input: "boo!", uuid: conversation.uuid } }

      it "returns 204 No Content" do
        post "/chat", params: params
        expect(response).to have_http_status(:no_content)
      end

      it "creates exactly one Turn" do
        expect { post "/chat", params: params }.to change(Turn, :count).by(1)
      end

      it "creates echo + thinking + a witty system Event (not an error) after the job runs" do
        perform_enqueued_jobs { post "/chat", params: params }
        turn = Turn.last
        expect(turn.events.map(&:kind)).to include("echo", "thinking", "system")
        expect(turn.events.map(&:kind)).not_to include("error")
      end

      it "broadcasts echo to the conversation stream immediately" do
        stream = "pito:conversation:#{conversation.uuid}"
        expect { post "/chat", params: params }.to have_broadcasted_to(stream).at_least(:once)
      end
    end

    context "with a recognised chat verb (list)" do
      # `list games` is a fully-wired chat verb that yields a system event;
      # `list videos` is recognised but not listable yet (videos deferred).
      let(:params) { { input: "list games", uuid: conversation.uuid } }

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
    end

    context "channel + period context" do
      it "does NOT forward channel/period to the job for slash commands" do
        expect {
          post "/chat", params: { input: "/help", uuid: conversation.uuid, channel: "@gaming", period: "7d" }
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: nil, period: nil))
      end

      it "forwards channel/period to the job for chat messages" do
        expect {
          post "/chat", params: { input: "show me stats", uuid: conversation.uuid, channel: "@gaming", period: "7d" }
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: "@gaming", period: "7d"))
      end

      it "defaults channel to @all for chat messages when not provided" do
        expect {
          post "/chat", params: { input: "show me stats", uuid: conversation.uuid }
        }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(channel: "@all"))
      end
    end

    context "with no-verb input (unknown classification)" do
      before do
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

    context "with a confirmation response (#handle confirm|cancel) via the follow-up engine" do
      let(:conf_turn) do
        conversation.turns.create!(
          input_kind: :slash, input_text: "/disconnect @pito", position: 1
        )
      end
      let!(:confirmation_event) do
        Event.create_with_position!(
          conversation:, turn: conf_turn,
          kind: "confirmation",
          payload: {
            "command"       => "disconnect",
            "body"          => "Disconnect from @pito?",
            "reply_handle"  => "gamma-4242",
            "reply_target"  => "confirmation",
            "channel_id"    => 0,
            "authenticated" => true
          }
        )
      end

      before do
        # Ensure the handler is loaded + registered (lazy-load in test env).
        Pito::FollowUp::Handlers::Confirmation
        Pito::FollowUp::Registry.register(Pito::FollowUp::Handlers::Confirmation)
      end

      it "returns 204 No Content" do
        post "/chat", params: { input: "#gamma-4242 confirm", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end

      it "creates a new echo Turn (append mode)" do
        expect {
          post "/chat", params: { input: "#gamma-4242 confirm", uuid: conversation.uuid }
        }.to change(Turn, :count).by(1)
      end

      it "creates an echo Event" do
        post "/chat", params: { input: "#gamma-4242 confirm", uuid: conversation.uuid }
        echo = Turn.last.events.find { |e| e.kind == "echo" }
        expect(echo).to be_present
      end

      it "enqueues FollowUpDispatchJob with the event id and rest" do
        post "/chat", params: { input: "#gamma-4242 confirm", uuid: conversation.uuid }
        turn_id = Turn.last.id
        expect(FollowUpDispatchJob).to have_been_enqueued.with(
          confirmation_event.id,
          hash_including(rest: "confirm", turn_id: turn_id)
        )
      end

      it "silently 204s when handle is not found (consumed or unknown)" do
        post "/chat", params: { input: "#nosuch-0000 confirm", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end
    end

    context "with an analyze command (channel scope, fan-out)" do
      # A usable channel (youtube_connection, needs_reauth: false) so
      # AnalyzePrepareJob can reach the fan-out.
      let!(:test_channel) { create(:channel, :on_connection, handle: "gmrdad82") }

      # Stub the analytics fan-out → per metric, pulled (true → "1") or not
      # (false → "0"). Isolates the request flow from the YouTube report calls.
      before do
        allow(Pito::Analytics::Scaffold).to receive(:for).and_return(
          { views: true, subs: true, likes: false, watched_hours: true,
            avg_view_duration: false, avg_viewed_pct: true, comments: true, subscribed_status: false }
        )
        # :system Views is now a chart → stub its daily-series fetch too.
        allow(Pito::Analytics::DailySeries).to receive(:for).and_return(
          Pito::Analytics::DailySeries::Result.new(dates: [], series: [ 1, 2, 3 ], total: 6)
        )
        allow(Pito::Analytics::Thresholds).to receive(:subs_for).and_return(70)
      end

      it "returns 204 No Content" do
        post "/chat", params: { input: "analyze channel @gmrdad82", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end

      context "after draining all enqueued jobs" do
        before do
          perform_enqueued_jobs do
            post "/chat", params: { input: "analyze channel @gmrdad82", uuid: conversation.uuid }
          end
        end

        let(:the_turn)        { Turn.last }
        let(:analyze_events)  { the_turn.events.to_a.select { |e| e.payload.is_a?(Hash) && e.payload.key?("analyze") } }
        let(:thinking_events) { the_turn.events.where(kind: :thinking).to_a }

        it "persists exactly two analyze events" do
          expect(analyze_events.count).to eq(2)
        end

        it "both analyze events are ready" do
          expect(analyze_events).to all(satisfy { |e| e.payload.dig("analyze", "status") == "ready" })
        end

        it "both ready bodies render the 0/1 scaffold cells" do
          expect(analyze_events).to all(satisfy { |e| e.payload["body"].include?("pito-analytics-scalars") })
          joined = analyze_events.map { |e| e.payload["body"] }.join
          expect(joined).to include(">1<").and(include(">0<"))
        end

        it "all thinking indicators are resolved" do
          expect(thinking_events).to all(satisfy { |t| t.payload["resolved"] == true })
        end

        it "all thinking indicators have elapsed_seconds stamped (fan-out timing proof)" do
          expect(thinking_events).to all(satisfy { |t| t.payload["elapsed_seconds"].is_a?(Numeric) })
        end

        it "turn is completed" do
          expect(the_turn.reload.completed_at).not_to be_nil
        end
      end
    end

    # ── follow-up: glance → analyze pair (append) ─────────────────────────────

    context "with a glance reply (#<handle> with views) — glance → analyze pair" do
      let!(:channel) { create(:channel, :on_connection) }
      let!(:video)   { create(:video, channel:) }

      # The "show vid" turn that holds the analytics glance event.
      let!(:show_turn) do
        conversation.turns.create!(
          input_kind: :chat, input_text: "show vid ##{video.id}", position: 1
        )
      end

      # A ready glance event with a known handle.
      let!(:glance_event) do
        payload = {
          "body"      => "<div>glance</div>",
          "html"      => true,
          "anchor"    => true,
          "analytics" => {
            "status"     => "ready",
            "scope_type" => "Video",
            "scope_id"   => video.id,
            "period"     => "7d",
            "intro"      => "<span>intro</span>"
          },
          "reply_handle" => "alpha-1234",
          "reply_target" => "analytics_glance"
        }
        Event.create_with_position!(
          conversation:, turn: show_turn, kind: :enhanced, payload:
        )
      end

      before do
        # Ensure handlers are loaded + registered for this test.
        Pito::FollowUp::Handlers::AnalyticsGlance
        Pito::FollowUp::Registry.register(Pito::FollowUp::Handlers::AnalyticsGlance)
        Pito::FollowUp::Handlers::AnalyzeMessage
        Pito::FollowUp::Registry.register(Pito::FollowUp::Handlers::AnalyzeMessage)

        # Stub Scaffold.for so AnalyzePrepareJob never hits YouTube.
        allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
          Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
        end
        # :system Views is now a chart → stub its daily-series fetch too.
        allow(Pito::Analytics::DailySeries).to receive(:for).and_return(
          Pito::Analytics::DailySeries::Result.new(dates: [], series: [ 1, 2, 3 ], total: 6)
        )
        allow(Pito::Analytics::Thresholds).to receive(:subs_for).and_return(70)
      end

      it "returns 204 No Content" do
        post "/chat", params: { input: "#glance-req-test with views", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end

      context "after draining all enqueued jobs" do
        before do
          perform_enqueued_jobs do
            post "/chat", params: { input: "#alpha-1234 with views", uuid: conversation.uuid }
          end
        end

        # The FollowUpDispatchJob creates events in the new echo turn; AnalyzePrepareJob fills them.
        let(:analyze_events) do
          Event.joins(:turn)
            .where(turns: { conversation_id: conversation.id })
            .select { |e| e.payload.is_a?(Hash) && e.payload.key?("analyze") }
        end

        it "persists exactly two analyze events (system + enhanced pair)" do
          expect(analyze_events.count).to eq(2)
        end

        it "both analyze events are ready (AnalyzePrepareJob ran)" do
          expect(analyze_events).to all(satisfy { |e| e.payload.dig("analyze", "status") == "ready" })
        end

        it "both analyze events are followupable with reply_target: 'analyze_message'" do
          expect(analyze_events).to all(satisfy { |e| e.payload["reply_target"] == "analyze_message" })
        end

        it "the glance event is consumed (reply_consumed: true)" do
          expect(glance_event.reload.payload["reply_consumed"]).to be true
        end
      end
    end

    # ── follow-up: analyze mutate (without <metric>) ──────────────────────────

    context "with an analyze reply (#<handle> without comms) — mutate in place" do
      # Build a ready analyze payload directly (no DB round-trip needed).
      let(:scaffold) do
        Pito::Analytics::MetricOrder.for(role: :system, level: :channel).index_with { true }
      end

      let!(:analyze_turn) do
        conversation.turns.create!(
          input_kind: :chat, input_text: "analyze channel", position: 1
        )
      end

      let!(:analyze_event) do
        # Build the ready payload directly.  The body is a placeholder — the
        # test only checks the marker, not the rendered HTML.
        ready_p = {
          "body"    => "<div>analyze body</div>",
          "html"    => true,
          "anchor"  => true,
          "analyze" => {
            "status"     => "ready",
            "role"       => "system",
            "title"      => "My Channel",
            "level"      => "channel",
            "entity_ids" => [ 1 ],
            "period"     => "7d",
            "intro"      => "<span>intro</span>",
            "scaffold"   => scaffold.transform_keys(&:to_s),
            "with"       => [],
            "without"    => []
          },
          "reply_handle" => "beta-5678",
          "reply_target" => "analyze_message"
        }
        Event.create_with_position!(
          conversation:, turn: analyze_turn, kind: :system, payload: ready_p
        )
      end

      before do
        Pito::FollowUp::Handlers::AnalyzeMessage
        Pito::FollowUp::Registry.register(Pito::FollowUp::Handlers::AnalyzeMessage)
      end

      it "returns 204 No Content" do
        post "/chat", params: { input: "#beta-5678 without comms", uuid: conversation.uuid }
        expect(response).to have_http_status(:no_content)
      end

      context "after draining the enqueued job" do
        before do
          perform_enqueued_jobs do
            post "/chat", params: { input: "#beta-5678 without comms", uuid: conversation.uuid }
          end
        end

        it "mutates the analyze event in place (comms alias → canonical comments in without)" do
          expect(analyze_event.reload.payload.dig("analyze", "without")).to include("comments")
        end

        it "does NOT consume the handle (reply_consumed is absent/false)" do
          consumed = analyze_event.reload.payload["reply_consumed"]
          expect(consumed).to be_falsey
        end

        it "does NOT create a new turn for the mutate path" do
          # Only the analyze_turn from setup exists; mutate creates no echo turn.
          expect(Turn.where(conversation:).count).to eq(1)
        end
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
