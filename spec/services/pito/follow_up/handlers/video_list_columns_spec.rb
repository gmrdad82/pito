# frozen_string_literal: true

require "rails_helper"

# Specs for the add/remove column-mutation feature on the video_list follow-up handler.
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

  it "declares the video_list target in :append mode (default)" do
    expect(described_class.target).to eq("video_list")
    expect(described_class.mode).to eq(:append)
  end

  it "declares add and remove as :mutate per-action overrides" do
    expect(described_class.action_modes["add"]).to eq(:mutate)
    expect(described_class.action_modes["remove"]).to eq(:mutate)
  end

  it "includes add and remove in declared actions" do
    expect(described_class.actions).to include("add", "remove")
  end

  # ── Registry.mode_for (per-action) ──────────────────────────────────────────

  describe "Pito::FollowUp::Registry.mode_for (per-action)" do
    before { Pito::FollowUp::Registry.register_all! }

    it "returns :mutate for add action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "add")).to eq(:mutate)
    end

    it "returns :mutate for remove action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "remove")).to eq(:mutate)
    end

    it "returns :append for show action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "show")).to eq(:append)
    end

    it "returns :append for delete action" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "delete")).to eq(:append)
    end
  end

  # ── add <columns> ───────────────────────────────────────────────────────────

  describe "#call with add" do
    it "returns a Mutation for add game" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind is :system (mirrors the source event kind)" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "payload includes game in list_columns after add game" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result.payload["list_columns"]).to include("game")
    end

    it "payload table_heading gains Game column after add" do
      result = handler.call(event:, rest: "add game", conversation:)
      heading_texts = result.payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to include("Game")
    end

    it "does NOT set reply_consumed (handle is NOT consumed)" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle" do
      original_handle = event_payload["reply_handle"]
      result          = handler.call(event:, rest: "add game", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end

    it "preserves reply_target as video_list" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result.payload["reply_target"]).to eq("video_list")
    end

    it "accepts comma-separated columns: add game, duration" do
      result = handler.call(event:, rest: "add game, duration", conversation:)
      expect(result.payload["list_columns"]).to include("game", "duration")
    end

    it "ignores unknown column tokens (no error)" do
      result = handler.call(event:, rest: "add banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to eq([])
    end

    it "stamps video_ids in the rebuilt payload" do
      result = handler.call(event:, rest: "add game", conversation:)
      expect(result.payload["video_ids"]).to eq([ video.id ])
    end

    it "ignores duplicate columns (idempotent add)" do
      payload_with_game = Pito::MessageBuilder::Video::List.call(
        [ video ],
        conversation: conversation,
        columns:      [ :game ]
      )
      ev_with = instance_double(Event, payload: payload_with_game, kind: "system")

      result = handler.call(event: ev_with, rest: "add game", conversation:)
      expect(result.payload["list_columns"].count { |c| c == "game" }).to eq(1)
    end
  end

  # ── remove <columns> ────────────────────────────────────────────────────────

  describe "#call with remove" do
    let(:event_with_duration) do
      payload = Pito::MessageBuilder::Video::List.call(
        [ video ],
        conversation: conversation,
        columns:      [ :duration ]
      )
      instance_double(Event, payload:, kind: "system")
    end

    it "returns a Mutation for remove duration" do
      result = handler.call(event: event_with_duration, rest: "remove duration", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "duration is removed from list_columns" do
      result = handler.call(event: event_with_duration, rest: "remove duration", conversation:)
      expect(result.payload["list_columns"]).not_to include("duration")
    end

    it "ignores unknown column in remove (no error)" do
      result = handler.call(event: event_with_duration, rest: "remove banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to include("duration")
    end

    it "does NOT consume the handle" do
      result = handler.call(event: event_with_duration, rest: "remove duration", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
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

  # ── show/delete still go through VerbDelegator (:append, consuming) ─────────

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
