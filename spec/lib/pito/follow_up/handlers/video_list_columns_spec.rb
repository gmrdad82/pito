# frozen_string_literal: true

require "rails_helper"

# Specs for the with/without column-mutation feature on the video_list follow-up handler.
RSpec.describe Pito::FollowUp::Handlers::VideoList, "column mutations" do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, handle: "@chan", youtube_channel_id: "UCvl_col1") }
  let!(:video)       { create(:video, :public, title: "Boss Rush", channel:) }

  # Build a realistic video_list event payload using the List builder so it carries
  # video_ids and list_columns (as produced by MessageBuilder::Video::List.call).
  let(:event_payload) do
    Pito::MessageBuilder::Video::List.call(
      [ video ],
      conversation: conversation,
      columns:      []
    )
  end

  let(:event) do
    instance_double(Event,
      payload: event_payload,
      kind:    "system")
  end

  # ── Handler class declarations ──────────────────────────────────────────────

  it "registers the video_list target" do
    expect(described_class.target).to eq("video_list")
  end

  it "Matrix serves :append base mode for video_list" do
    expect(Pito::Dispatch::Matrix.mode_for("video_list")).to eq(:append)
  end

  it "Matrix serves :mutate for with and without on video_list" do
    expect(Pito::Dispatch::Matrix.mode_for("video_list", action: "with")).to eq(:mutate)
    expect(Pito::Dispatch::Matrix.mode_for("video_list", action: "without")).to eq(:mutate)
  end

  it "Matrix advertises with and without for video_list" do
    expect(Pito::Dispatch::Matrix.actions_for("video_list")).to include("with", "without")
  end

  it "Matrix does not advertise the dropped add/remove verbs for video_list" do
    actions = Pito::Dispatch::Matrix.actions_for("video_list")
    expect(actions).not_to include("add", "remove")
    # Unknown tokens fall back to the target's base mode (HF3 — DSL parity);
    # non-advertisement is the actions_for assertion above.
    base = Pito::Dispatch::Matrix.mode_for("video_list", action: nil)
    expect(Pito::Dispatch::Matrix.mode_for("video_list", action: "add")).to eq(base)
    expect(Pito::Dispatch::Matrix.mode_for("video_list", action: "remove")).to eq(base)
  end

  # ── Registry.mode_for (per-action) ──────────────────────────────────────────

  describe "Pito::FollowUp::Registry.mode_for (per-action)" do
    before { Pito::FollowUp::Registry.register_all! }

    it "returns :mutate for with action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "with")).to eq(:mutate)
    end

    it "returns :mutate for without action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "without")).to eq(:mutate)
    end

    it "returns :append for show action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "show")).to eq(:append)
    end

    it "returns :append for delete action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "delete")).to eq(:append)
    end
  end

  # ── with <columns> ──────────────────────────────────────────────────────────

  describe "#call with `with`" do
    it "returns a Mutation for with game" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind is :system (mirrors the source event kind)" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "payload includes game in list_columns after with game" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload["list_columns"]).to include("game")
    end

    it "payload table_heading gains Game column after with" do
      result = handler.call(event:, rest: "with game", conversation:)
      heading_texts = result.payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to include("Game")
    end

    it "does NOT set reply_consumed (handle is NOT consumed)" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle" do
      original_handle = event_payload["reply_handle"]
      result          = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end

    it "preserves reply_target as video_list" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload["reply_target"]).to eq("video_list")
    end

    it "does NOT elevate the mutated segment (payload[:surface] removed 2026-07-01)" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload).not_to have_key("surface")
    end

    it "accepts comma-separated columns: with game, duration" do
      result = handler.call(event:, rest: "with game, duration", conversation:)
      expect(result.payload["list_columns"]).to include("game", "duration")
    end

    it "ignores unknown column tokens (no error)" do
      result = handler.call(event:, rest: "with banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to eq([])
    end

    it "stamps video_ids in the rebuilt payload" do
      result = handler.call(event:, rest: "with game", conversation:)
      expect(result.payload["video_ids"]).to eq([ video.id ])
    end

    it "ignores duplicate columns (idempotent with)" do
      payload_with_game = Pito::MessageBuilder::Video::List.call(
        [ video ],
        conversation: conversation,
        columns:      [ :game ]
      )
      ev_with = instance_double(Event, payload: payload_with_game, kind: "system")

      result = handler.call(event: ev_with, rest: "with game", conversation:)
      expect(result.payload["list_columns"].count { |c| c == "game" }).to eq(1)
    end
  end

  # ── without <columns> ─────────────────────────────────────────────────────────

  describe "#call with `without`" do
    let(:event_with_duration) do
      payload = Pito::MessageBuilder::Video::List.call(
        [ video ],
        conversation: conversation,
        columns:      [ :duration ]
      )
      instance_double(Event, payload:, kind: "system")
    end

    it "returns a Mutation for without duration" do
      result = handler.call(event: event_with_duration, rest: "without duration", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "duration is removed from list_columns" do
      result = handler.call(event: event_with_duration, rest: "without duration", conversation:)
      expect(result.payload["list_columns"]).not_to include("duration")
    end

    it "ignores unknown column in without (no error)" do
      result = handler.call(event: event_with_duration, rest: "without banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to include("duration")
    end

    it "does NOT consume the handle" do
      result = handler.call(event: event_with_duration, rest: "without duration", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end
  end

  # ── single-channel suppression ────────────────────────────────────────────
  # A per-list-suppressed column (e.g. :channel on a single-channel result
  # set) must stay rejected across replies — "with channel" neither crashes
  # nor re-adds the column; other columns are untouched; the suppression
  # itself carries forward on every rebuilt payload.

  describe "#call on a channel-suppressed list" do
    let(:suppressed_event_payload) do
      Pito::MessageBuilder::Video::List.call(
        [ video ],
        conversation:,
        columns:            [ :visibility ],
        suppressed_columns: [ :channel ]
      )
    end

    let(:suppressed_event) do
      instance_double(Event, payload: suppressed_event_payload, kind: "system")
    end

    it "rejects `with channel` — no error, same silent no-op as any unknown column" do
      result = handler.call(event: suppressed_event, rest: "with channel", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).not_to include("channel")
    end

    it "`without channel` is a no-op (already absent, never a crash)" do
      result = handler.call(event: suppressed_event, rest: "without channel", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).not_to include("channel")
    end

    it "`with duration` on the same suppressed list still works (other columns untouched)" do
      result = handler.call(event: suppressed_event, rest: "with duration", conversation:)
      expect(result.payload["list_columns"]).to include("visibility", "duration")
      expect(result.payload["list_columns"]).not_to include("channel")
    end

    it "carries suppressed_columns forward on the rebuilt payload" do
      result = handler.call(event: suppressed_event, rest: "with duration", conversation:)
      expect(result.payload["suppressed_columns"]).to eq([ "channel" ])
    end

    it "carries suppressed_columns forward through a sort mutation too" do
      result = handler.call(event: suppressed_event, rest: "sort by title", conversation:)
      expect(result.payload["suppressed_columns"]).to eq([ "channel" ])
    end

    context "when the list_cursor already carries suppressed_columns" do
      let(:cursor_event) do
        instance_double(Event, kind: "system", payload: suppressed_event_payload.merge(
          "list_cursor" => {
            "offset" => 1, "channel" => nil, "filter" => nil,
            "sort_token" => nil, "sort_direction" => nil,
            "columns" => %w[visibility], "suppressed_columns" => %w[channel]
          }
        ))
      end

      it "keeps suppressed_columns in the cursor after a with mutation" do
        result = handler.call(event: cursor_event, rest: "with duration", conversation:)
        expect(result.payload["list_cursor"]["suppressed_columns"]).to eq([ "channel" ])
      end
    end
  end

  # ── add/remove are now INVALID (dropped entirely, not aliased) ───────────────

  describe "#call with the dropped add/remove verbs" do
    before { Pito::FollowUp::Registry.register_all! }

    it "rejects `add` with the invalid_action error (no longer a column verb)" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_list.errors.invalid_action")
      expect(result.message_args).to eq({ action: "add" })
    end

    it "rejects `remove` with the invalid_action error" do
      result = handler.call(event:, rest: "remove game", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_list.errors.invalid_action")
    end
  end

  # ── sort/order <column> ─────────────────────────────────────────────────────

  describe "#call with sort" do
    let(:channel2) { create(:channel, handle: "@chan2", youtube_channel_id: "UCvl_col2") }
    let!(:vid_a)   { create(:video, :public, title: "Aardvark Run",  channel:) }
    let!(:vid_b)   { create(:video, :public, title: "Zebra Chase",   channel:) }

    let(:two_video_event) do
      payload = Pito::MessageBuilder::Video::List.call(
        [ vid_b, vid_a ],   # intentionally out of alpha order
        conversation:,
        columns: []
      )
      instance_double(Event, payload:, kind: "system")
    end

    it "returns a Mutation for sort by title" do
      result = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind is :system (mirrors the source event kind)" do
      result = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "re-sorts the list ascending by title" do
      result = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result.payload["video_ids"]).to eq([ vid_a.id, vid_b.id ])
    end

    it "re-sorts descending with `sort by title desc`" do
      result = handler.call(event: two_video_event, rest: "sort by title desc", conversation:)
      expect(result.payload["video_ids"]).to eq([ vid_b.id, vid_a.id ])
    end

    it "accepts `sort title` (without `by`)" do
      result = handler.call(event: two_video_event, rest: "sort title", conversation:)
      expect(result.payload["video_ids"]).to eq([ vid_a.id, vid_b.id ])
    end

    it "`order by title` is an alias for sort" do
      result = handler.call(event: two_video_event, rest: "order by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["video_ids"]).to eq([ vid_a.id, vid_b.id ])
    end

    it "is a lenient no-op for an unknown column (stamped order preserved)" do
      result = handler.call(event: two_video_event, rest: "sort by banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      # Stamped order was [vid_b, vid_a] (no key found → unchanged)
      expect(result.payload["video_ids"]).to eq([ vid_b.id, vid_a.id ])
    end

    it "is a lenient no-op when sorting by a column not present in the list (views requires with)" do
      result = handler.call(event: two_video_event, rest: "sort by views", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["video_ids"]).to eq([ vid_b.id, vid_a.id ])
    end

    it "does NOT set reply_consumed (handle stays live)" do
      result = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle" do
      original_handle = two_video_event.payload["reply_handle"]
      result          = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end

    it "preserves reply_target as video_list" do
      result = handler.call(event: two_video_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_target"]).to eq("video_list")
    end

    context "when the views column is present" do
      before do
        Pito::Stats.set(vid_a, :views, 100)
        Pito::Stats.set(vid_b, :views, 9000)
      end

      let(:views_event) do
        payload = Pito::MessageBuilder::Video::List.call(
          [ vid_a, vid_b ],
          conversation:,
          columns: [ :views ]
        )
        instance_double(Event, payload:, kind: "system")
      end

      it "sorts by views ascending when the views column is present" do
        result = handler.call(event: views_event, rest: "sort by views", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        # vid_a has 100 views, vid_b has 9000 → ascending order: a, b
        expect(result.payload["video_ids"]).to eq([ vid_a.id, vid_b.id ])
      end

      it "sorts by views descending" do
        result = handler.call(event: views_event, rest: "sort by views desc", conversation:)
        expect(result.payload["video_ids"]).to eq([ vid_b.id, vid_a.id ])
      end
    end
  end

  describe "Pito::FollowUp::Registry.mode_for — sort/order" do
    before { Pito::FollowUp::Registry.register_all! }

    it "returns :mutate for sort action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "sort")).to eq(:mutate)
    end

    it "returns :mutate for order action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "order")).to eq(:mutate)
    end
  end

  # ── show/delete still go through ToolDelegator (:append, consuming) ─────────

  describe "#call with show (still :append, consuming)" do
    it "returns an Append result for show" do
      result = handler.call(event:, rest: "show ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end
  end

  describe "#call with delete (still :append, consuming)" do
    it "returns an Append result for delete" do
      result = handler.call(event:, rest: "delete ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind].to_s).to eq("confirmation")
    end
  end
end
