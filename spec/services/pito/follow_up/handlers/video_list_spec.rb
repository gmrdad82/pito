# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::VideoList do
  include ActiveSupport::Testing::TimeHelpers

  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, handle: "@chan", youtube_channel_id: "UCvl1") }
  let!(:video)       { create(:video, :public, title: "Boss Rush", channel:) }

  # A video_list source event whose only row is `video` (#id in the first cell).
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "video_list",
      "table_rows"   => [ { cells: [ { text: "##{video.id}" }, { text: video.title } ] } ]
    })
  end

  it "registers for the video_list target" do
    expect(described_class.target).to eq("video_list")
  end

  it "Matrix serves :append mode for video_list" do
    expect(Pito::Dispatch::Matrix.mode_for("video_list")).to eq(:append)
  end

  describe "analyze" do
    let(:other) { create(:video, :public, title: "Second", channel:) }
    let(:list_event) do
      instance_double(Event, payload: { "reply_target" => "video_list", "video_ids" => [ video.id, other.id ] })
    end

    it "`analyze #<id>` analyzes ONLY that vid (subject = its title, not 'N vids')" do
      expect(Pito::FollowUp::AnalyzeReply).to receive(:append).with(level: :vid, ids: [ video.id ], conversation:, period: nil)
      handler.call(event: list_event, rest: "analyze ##{video.id}", conversation:)
    end

    it "bare `analyze` analyzes the whole listed scope" do
      expect(Pito::FollowUp::AnalyzeReply).to receive(:append).with(level: :vid, ids: [ video.id, other.id ], conversation:, period: nil)
      handler.call(event: list_event, rest: "analyze", conversation:)
    end
  end

  it "delegates `show <id>` to the video verb handler: bare → the detail card only" do
    result = handler.call(event:, rest: "show ##{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)

    # Bare show → detail only (plan-0.9.5 D3).
    expect(result.events.map { |e| e[:kind] }).to eq([ :system ])
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["body"]).to include("Boss Rush")
    expect(detail["reply_target"]).to eq("video_detail")
    expect(detail["video_id"]).to eq(video.id)
  end

  it "resolves `show <id>` by VIDEO id (not game) — reply_target fixes entity type" do
    # Even without the 'video' noun in rest, the entity type is VIDEO
    # because reply_target = 'video_list' drives video_target? in the Show handler.
    result = handler.call(event:, rest: "show ##{video.id}", conversation:)
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["video_id"]).to eq(video.id)
    expect(detail["reply_target"]).to eq("video_detail")
  end

  it "returns not-found for a title ref (show is id-only — no title lookup)" do
    result = handler.call(event:, rest: "show boss rush", conversation:)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["video_id"]).to be_nil
  end

  it "appends a witty not-found for an unknown reference" do
    result = handler.call(event:, rest: "show 9999", conversation:)
    expect(result.events.first[:payload]["text"]).to include("9999")
  end

  it "rejects an invalid action (not in the video_list matrix)" do
    result = handler.call(event:, rest: "channel 5", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Error)
  end

  it "delegates `delete <id>` / `rm <id>` to the video delete confirmation" do
    result = handler.call(event:, rest: "rm ##{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("video_delete")
  end

  it "delegates `delete <id>` to the video delete confirmation (delete alias)" do
    result = handler.call(event:, rest: "delete ##{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("video_delete")
    expect(ev[:payload]["video_id"]).to eq(video.id)
  end

  # ── schedule / publish / unlist (single-vid state verbs, :append) ────────────

  # `today at 14:30` must land in the future for a confirmation (else the handler
  # emits a witty past/too-soon event) — freeze the clock to this morning.
  context "schedule replies (clock frozen to 2026-06-20 09:00)" do
    around { |example| travel_to(Time.zone.local(2026, 6, 20, 9, 0)) { example.run } }

    it "delegates `schedule <#id> today at 14:30` to the schedule confirmation" do
      result = handler.call(event:, rest: "schedule ##{video.id} today at 14:30", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      ev = result.events.first
      expect(ev[:kind].to_s).to eq("confirmation")
      expect(ev[:payload]["command"]).to eq("video_schedule")
      expect(ev[:payload]["video_id"]).to eq(video.id)
    end

    it "delegates `schedule <id> today at 14:30` with a bare (no-#) id" do
      result = handler.call(event:, rest: "schedule #{video.id} today at 14:30", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      ev = result.events.first
      expect(ev[:kind].to_s).to eq("confirmation")
      expect(ev[:payload]["command"]).to eq("video_schedule")
      expect(ev[:payload]["video_id"]).to eq(video.id)
    end
  end

  it "delegates `publish <#id>` to the publish confirmation" do
    result = handler.call(event:, rest: "publish ##{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("video_publish")
  end

  it "delegates `unlist <id>` (bare id) to the unlist confirmation" do
    result = handler.call(event:, rest: "unlist #{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("video_unlist")
  end

  # ── link / unlink (source: video, target: game) ─────────────────────────────

  # ── shinies (delegated to Chat::Handlers::Shinies via VerbDelegator) ───────────

  describe "#call — shinies" do
    it "returns a Result::Append with the shinies message for the referenced video" do
      result = handler.call(event:, rest: "shinies ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["video_id"]).to eq(video.id)
    end

    it "does NOT return an invalid_action error (shinies is now a declared action)" do
      result = handler.call(event:, rest: "shinies ##{video.id}", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
  end

  context "link and unlink verbs (source: video, target: game)" do
    let!(:game) { create(:game, title: "Lies of P") }

    # The outer `event` has reply_target: "video_list" and no singular video_id
    # in its payload, which correctly signals the list context to follow_up_multi.

    it "link <video_id> to <game_id> creates a VideoGameLink and returns an Append" do
      result = handler.call(event:, rest: "link #{video.id} to #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(true)
    end

    it "link result has consume: false so the list card stays reusable" do
      result = handler.call(event:, rest: "link #{video.id} to #{game.id}", conversation:)
      expect(result.consume).to be(false)
    end

    it "link <video_id> to <g1>,<g2> creates both VideoGameLinks (multi-target)" do
      game2  = create(:game, title: "Sekiro")
      result = handler.call(event:, rest: "link #{video.id} to #{game.id},#{game2.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(true)
      expect(VideoGameLink.exists?(video: video, game: game2)).to be(true)
    end

    it "unlink <video_id> from <game_id> destroys the VideoGameLink and returns an Append" do
      VideoGameLink.create!(video: video, game: game)
      result = handler.call(event:, rest: "unlink #{video.id} from #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(false)
    end

    it "unlink result has consume: false so the list card stays reusable" do
      VideoGameLink.create!(video: video, game: game)
      result = handler.call(event:, rest: "unlink #{video.id} from #{game.id}", conversation:)
      expect(result.consume).to be(false)
    end
  end

  # ── `next` pagination ────────────────────────────────────────────────────────
  # Stub page_size to 2 so we can use tiny fixtures.

  # #12 regression — a `sort by` reply on a video list previously DROPPED the pager
  # cursor entirely (ending pagination). It must now be preserved AND carry the sort.
  describe "reply sort preserves + folds into the pager cursor (#12)" do
    let!(:v_a) { create(:video, :public, title: "Zeta Run",  channel:) }
    let!(:v_b) { create(:video, :public, title: "Alpha Run", channel:) }

    let(:cursor_event) do
      instance_double(Event, kind: "system", payload: {
        "reply_target" => "video_list",
        "video_ids"    => [ video.id, v_a.id, v_b.id ],
        "list_columns" => [],
        "list_cursor"  => {
          "offset" => 2, "channel" => nil, "filter" => nil,
          "sort_token" => nil, "sort_direction" => nil, "columns" => []
        }
      })
    end

    it "keeps the list_cursor (was dropped before) and records the new sort" do
      result = handler.call(event: cursor_event, rest: "sort by title", conversation:)
      cursor = result.payload["list_cursor"]
      expect(cursor).not_to be_nil
      expect(cursor["sort_token"]).to eq("title")
      expect(cursor["sort_direction"]).to eq("asc")
    end
  end

  describe "`next` pagination" do
    let(:pager_stub) { { page_size: 2, more_verb: "next" } }
    let!(:v2) { create(:video, :public, title: "Raid Run",   channel:) }
    let!(:v3) { create(:video, :public, title: "Boss Guide", channel:) }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager)
        .with(verb: :list)
        .and_return(pager_stub)
    end

    # Cursor stamped after showing 2 of 3 videos (offset=2).
    let(:cursor_event) do
      instance_double(Event, payload: {
        "reply_target" => "video_list",
        "list_cursor"  => {
          "offset"         => 2,
          "channel"        => nil,
          "filter"         => nil,
          "sort_token"     => nil,
          "sort_direction" => nil,
          "columns"        => []
        }
      })
    end

    it "renders the final batch (1 video) with no list_cursor" do
      result = handler.call(event: cursor_event, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["list_cursor"]).to be_nil
    end

    # #5: `more` is a per-target reply alias of `next` and must page identically.
    it "`more` pages identically to `next`" do
      result = handler.call(event: cursor_event, rest: "more", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["list_cursor"]).to be_nil
    end

    context "mid-batch: 5 videos, page_size=2, offset=2" do
      let!(:v4) { create(:video, :public, title: "Speed Run", channel:) }
      let!(:v5) { create(:video, :public, title: "Unboxing",  channel:) }

      let(:mid_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "video_list",
          "list_cursor"  => {
            "offset"         => 2,
            "channel"        => nil,
            "filter"         => nil,
            "sort_token"     => nil,
            "sort_direction" => nil,
            "columns"        => []
          }
        })
      end

      it "list_footer for mid-batch `next` contains count (2) and total (5)" do
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("2")
        expect(footer).to include("5")
      end

      it "rest = total − (offset + count) = 1 is reflected in footer" do
        # Force variant 1 which uses %{rest}: "%{count} here, %{rest} more in the system. `%{verb}`."
        Pito::Copy.sampler = ->(entries) { entries[1] }
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("1 more in the system")
      end
    end

    context "no cursor (completed list)" do
      let(:no_cursor_event) do
        instance_double(Event, payload: { "reply_target" => "video_list" })
      end

      it "renders list_end copy" do
        result = handler.call(event: no_cursor_event, rest: "next", conversation:)
        text = result.events.first[:payload]["text"].to_s
        expect(text).to be_present
        expect(text).not_to match(/%\{/)
      end
    end
  end
end
