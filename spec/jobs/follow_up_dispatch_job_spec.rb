# frozen_string_literal: true

require "rails_helper"

# Fake mutate handler — registered only during this spec file.
class FakeMutateHandler < Pito::FollowUp::Handler
  target "fake_mutate"
  mode   :mutate

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Mutation.new(
      kind:    :enhanced,
      payload: event.payload.merge("done" => true, "rest" => rest)
    )
  end
end

# Fake append handler — registered only during this spec file.
class FakeAppendHandler < Pito::FollowUp::Handler
  target "fake_append"
  mode   :append

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Append.new(
      events: [
        { kind: :system, payload: { text: "appended by #{rest}" } }
      ]
    )
  end
end

# Fake append handler that passes consume: false so the source event stays live.
class FakeAppendNoConsumeHandler < Pito::FollowUp::Handler
  target "fake_append_no_consume"
  mode   :append

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Append.new(
      events:  [ { kind: :system, payload: { text: "no-consume" } } ],
      consume: false
    )
  end
end

# Fake append handler that emits a pending analytics :enhanced event.
# Uses a minimal hardcoded payload so no DB models are needed in the handler itself.
class FakeAppendAnalyticsHandler < Pito::FollowUp::Handler
  target "fake_append_analytics"
  mode   :append

  PENDING_ANALYTICS_PAYLOAD = {
    "html"      => true,
    "anchor"    => true,
    "analytics" => {
      "status"     => "pending",
      "scope_type" => "Video",
      "scope_id"   => 1,
      "period"     => "28d",
      "intro"      => "some intro"
    }
  }.freeze

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Append.new(
      events: [
        { kind: :system,   payload: { "text" => "show result" } },
        { kind: :enhanced, payload: PENDING_ANALYTICS_PAYLOAD }
      ]
    )
  end
end

# Fake error handler.
class FakeErrorHandler < Pito::FollowUp::Handler
  target "fake_error"
  mode   :mutate

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Error.new(
      message_key:  "pito.errors.something",
      message_args: {}
    )
  end
end

# Fake raising handler — used to exercise the D4 rescue path.
class FakeRaisingHandler < Pito::FollowUp::Handler
  target "fake_raising"
  mode   :mutate

  def call(event:, rest:, conversation:, **)
    raise RuntimeError, "handler exploded"
  end
end

class FakeRaisingAppendHandler < Pito::FollowUp::Handler
  target "fake_raising_append"
  mode   :append

  def call(event:, rest:, conversation:, **)
    raise RuntimeError, "append handler exploded"
  end
end

RSpec.describe FollowUpDispatchJob, type: :job do
  let(:conversation) { Conversation.create! }
  let(:source_turn) do
    conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 1)
  end

  # The pre-dispatch thinking placeholder the controller emits into the echo turn
  # before enqueueing the append job. The Finalizer REUSES it for the first
  # result message (so no extra Event is created and the spinner is continuous).
  def placeholder_thinking!(turn)
    Event.create_with_position!(
      conversation:, turn:, kind: :thinking,
      payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 2.seconds.ago.iso8601 }
    )
  end

  describe "Mutation result" do
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "alpha-1111",
          "reply_target" => "fake_mutate",
          "text"         => "original"
        }
      )
    end

    before do
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(
        instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil)
      )
    end

    it "updates the event kind" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.kind).to eq("enhanced")
    end

    it "merges done: true into the payload" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.payload["done"]).to be true
    end

    it "stores the rest string in the payload" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.payload["rest"]).to eq("do-it")
    end

    it "calls broadcaster.replace_event" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(broadcaster).to have_received(:replace_event).with(source_event)
    end

    it "emits pito:done so the dots fade out (turn-less mutate)" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(broadcaster).to have_received(:broadcast_done).with(dom_id: "event_#{source_event.id}")
    end

    # A :mutate reply (e.g. a video_list / analyze_message `with`/`without`) refines a
    # message IN PLACE — it is NOT a progression, so it must NEVER retire other live
    # #hashtags. The exemption is structural: mutate skips #persist entirely (where the
    # sweep lives), regardless of the mutated event's kind (:system, :enhanced, …).
    it "NEVER retires prior live hashtags (mutate bypasses the consume sweep)" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(broadcaster).not_to have_received(:consume_prior_live_replies)
    end
  end

  describe "Append result" do
    let!(:echo_turn) do
      conversation.turns.create!(input_kind: :hashtag, input_text: "#alpha-2222 run", position: 2)
        .tap { |t| placeholder_thinking!(t) }
    end
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "alpha-2222",
          "reply_target" => "fake_append",
          "text"         => "pick something"
        }
      )
    end

    it "creates a new event for each append result" do
      expect {
        described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      }.to change(Event, :count).by(1)
    end

    it "the new event has the correct kind and payload" do
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      new_event = echo_turn.events.last
      expect(new_event.kind).to eq("system")
      expect(new_event.payload["text"]).to eq("appended by hello")
    end

    it "marks the source event consumed" do
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      expect(source_event.reload.payload["reply_consumed"]).to be true
    end

    it "broadcasts replace_event on the (now-consumed) source" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      expect(broadcaster).to have_received(:replace_event).with(source_event)
    end

    context "consume gate" do
      it "does NOT set reply_consumed when consume: false — source stays live and events are appended" do
        no_consume_event = Event.create_with_position!(
          conversation:, turn: source_turn, kind: "system",
          payload: {
            "reply_handle" => "alpha-3333",
            "reply_target" => "fake_append_no_consume"
          }
        )
        extra_turn = conversation.turns.create!(
          input_kind: :hashtag, input_text: "#alpha-3333 go", position: 3
        )
        placeholder_thinking!(extra_turn)
        expect {
          described_class.perform_now(no_consume_event.id, rest: "go", turn_id: extra_turn.id)
        }.to change(Event, :count).by(1)
        expect(no_consume_event.reload.payload["reply_consumed"]).to be_nil
      end

      it "sets reply_consumed when consume: true (default) — source is consumed" do
        described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
        expect(source_event.reload.payload["reply_consumed"]).to be true
      end
    end

    context "when the Append result includes a pending analytics event" do
      let!(:analytics_source_event) do
        Event.create_with_position!(
          conversation:, turn: source_turn, kind: "system",
          payload: {
            "reply_handle" => "analytics-4444",
            "reply_target" => "fake_append_analytics"
          }
        )
      end

      let!(:analytics_turn) do
        conversation.turns.create!(
          input_kind: :hashtag,
          input_text: "#analytics-4444 show 21",
          position:   4
        ).tap { |t| placeholder_thinking!(t) }
      end

      it "enqueues AnalyticsFillJob with the turn id" do
        expect {
          described_class.perform_now(analytics_source_event.id, rest: "show 21", turn_id: analytics_turn.id)
        }.to have_enqueued_job(AnalyticsFillJob).with(analytics_turn.id)
      end

      it "does NOT call complete_turn itself when enqueueing the fill job" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil,
          resolve_thinking_for: nil, emit_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
        described_class.perform_now(analytics_source_event.id, rest: "show 21", turn_id: analytics_turn.id)
        expect(broadcaster).not_to have_received(:complete_turn)
      end

      it "does NOT bulk-resolve the turn's indicators when enqueueing the fill job (deferred to AnalyticsFillJob)" do
        # The READY messages' indicators are resolved per-message (resolve_thinking_for);
        # the pending analytics card's indicator is left spinning for the fill job.
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          replace_event: nil, broadcast_event: nil, broadcast_done: nil, resolve_thinking: nil,
          resolve_thinking_for: nil, emit_thinking: nil, complete_turn: nil, consume_prior_live_replies: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
        described_class.perform_now(analytics_source_event.id, rest: "show 21", turn_id: analytics_turn.id)
        expect(broadcaster).not_to have_received(:resolve_thinking)
      end
    end

    context "when the Append result has NO pending analytics event" do
      it "calls resolve_thinking then complete_turn immediately" do
        call_order = []
        broadcaster = instance_double(Pito::Stream::Broadcaster,
          replace_event: nil, broadcast_event: nil, broadcast_done: nil, consume_prior_live_replies: nil)
        allow(broadcaster).to receive(:resolve_thinking) { call_order << :resolve_thinking }
        allow(broadcaster).to receive(:complete_turn)    { call_order << :complete_turn }
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
        described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
        expect(broadcaster).to have_received(:resolve_thinking).with(turn: echo_turn)
        expect(broadcaster).to have_received(:complete_turn).with(turn: echo_turn)
        expect(call_order).to eq([ :resolve_thinking, :complete_turn ])
      end

      it "does NOT enqueue AnalyticsFillJob" do
        expect {
          described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
        }.not_to have_enqueued_job(AnalyticsFillJob)
      end
    end
  end

  describe "Error result" do
    let!(:echo_turn) do
      conversation.turns.create!(input_kind: :hashtag, input_text: "#err-5555 bad", position: 3)
        .tap { |t| placeholder_thinking!(t) }
    end
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "err-5555",
          "reply_target" => "fake_error"
        }
      )
    end

    it "appends an error event to the turn" do
      expect {
        described_class.perform_now(source_event.id, rest: "bad", turn_id: echo_turn.id)
      }.to change { echo_turn.events.where(kind: "error").count }.by(1)
    end

    it "calls resolve_thinking before complete_turn on handler error (D3)" do
      call_order = []
      broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_event: nil)
      allow(broadcaster).to receive(:resolve_thinking) { call_order << :resolve_thinking }
      allow(broadcaster).to receive(:complete_turn)    { call_order << :complete_turn }
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "bad", turn_id: echo_turn.id)
      expect(call_order).to eq([ :resolve_thinking, :complete_turn ])
    end
  end

  describe "missing handler (unknown target)" do
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: { "reply_handle" => "gamma-9999", "reply_target" => "nonexistent" }
      )
    end

    it "does not raise" do
      expect {
        described_class.perform_now(source_event.id, rest: "anything")
      }.not_to raise_error
    end
  end

  describe "D4 — rescue block surfaces error to scrollback" do
    context "append path (turn_id present) — handler raises" do
      let!(:echo_turn) do
        conversation.turns.create!(input_kind: :hashtag, input_text: "#raising-append-1 go", position: 5)
          .tap { |t| placeholder_thinking!(t) }
      end
      let!(:source_event) do
        Event.create_with_position!(
          conversation:, turn: source_turn, kind: "system",
          payload: {
            "reply_handle" => "raising-append-1",
            "reply_target" => "fake_raising_append"
          }
        )
      end

      it "re-raises the error so the job is marked failed" do
        expect {
          described_class.perform_now(source_event.id, rest: "go", turn_id: echo_turn.id)
        }.to raise_error(RuntimeError, "append handler exploded")
      end

      it "creates an :error event attached to the turn" do
        expect {
          described_class.perform_now(source_event.id, rest: "go", turn_id: echo_turn.id)
        }.to raise_error(RuntimeError)
          .and change { echo_turn.events.where(kind: "error").count }.by(1)
      end

      it "calls resolve_thinking and complete_turn before re-raising" do
        call_order = []
        broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_event: nil, resolve_thinking: nil, complete_turn: nil)
        allow(broadcaster).to receive(:resolve_thinking) { call_order << :resolve_thinking; nil }
        allow(broadcaster).to receive(:complete_turn)    { call_order << :complete_turn; nil }
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
        expect {
          described_class.perform_now(source_event.id, rest: "go", turn_id: echo_turn.id)
        }.to raise_error(RuntimeError)
        expect(call_order).to eq([ :resolve_thinking, :complete_turn ])
      end
    end

    context "mutate path (turn_id nil) — handler raises" do
      let!(:source_event) do
        Event.create_with_position!(
          conversation:, turn: source_turn, kind: "system",
          payload: {
            "reply_handle" => "raising-mutate-1",
            "reply_target" => "fake_raising"
          }
        )
      end

      it "re-raises the error so the job is marked failed" do
        expect {
          described_class.perform_now(source_event.id, rest: "go")
        }.to raise_error(RuntimeError, "handler exploded")
      end

      it "creates a minimal turn and an :error event" do
        expect {
          described_class.perform_now(source_event.id, rest: "go")
        }.to raise_error(RuntimeError)
          .and change(Turn, :count).by(1)
          .and change { Event.where(kind: "error").count }.by(1)
      end

      it "calls complete_turn before re-raising" do
        broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_event: nil, resolve_thinking: nil, complete_turn: nil)
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
        expect {
          described_class.perform_now(source_event.id, rest: "go")
        }.to raise_error(RuntimeError)
        expect(broadcaster).to have_received(:complete_turn)
      end
    end

    context "event_id does not exist — guard logs and re-raises without broadcasting" do
      it "re-raises without creating any events" do
        bad_id = 999_999_999
        expect {
          described_class.perform_now(bad_id, rest: "go")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
