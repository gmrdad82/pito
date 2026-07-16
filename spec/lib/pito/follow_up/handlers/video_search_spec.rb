# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::VideoSearch do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, handle: "@chan", youtube_channel_id: "UCvl1") }
  let!(:video)       { create(:video, :public, title: "Boss Rush", channel:) }

  # A video_search source event whose only row is `video` (#id in the first
  # cell) — same shape as VideoList's, but reply_target is "video_search".
  let(:event) do
    instance_double(Event, kind: "system", payload: {
      "reply_target" => "video_search",
      "video_ids"    => [ video.id ],
      "table_rows"   => [ { cells: [ { text: "##{video.id}" }, { text: video.title } ] } ]
    })
  end

  it "registers for the video_search target" do
    expect(described_class.target).to eq("video_search")
  end

  it "Matrix serves :append mode for video_search" do
    expect(Pito::Dispatch::Matrix.mode_for("video_search")).to eq(:append)
  end

  # ── pager (`next` / `more`) is rejected — a ranking is a single page ────────

  describe "pager is rejected (a similarity ranking has no next page)" do
    it "`next` returns the undeclared-action error, not a paginated list" do
      result = handler.call(event:, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "next")
    end

    it "`more` (the next alias) is rejected identically" do
      result = handler.call(event:, rest: "more", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "more")
    end
  end

  # ── sort (`sort` / `order`) is rejected — never scramble the ranking ────────

  describe "sort is rejected (the ranking is never re-sorted)" do
    it "`sort by title` returns the undeclared-action error" do
      result = handler.call(event:, rest: "sort by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "sort")
    end

    it "`order by title` (the sort alias) is rejected identically" do
      result = handler.call(event:, rest: "order by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "order")
    end
  end

  # ── analyze is rejected — no whole-scope re-analysis on a query ranking ────

  describe "analyze is rejected" do
    it "bare `analyze` returns the undeclared-action error" do
      result = handler.call(event:, rest: "analyze", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "analyze")
    end

    it "`analyze ##{id}` is rejected identically (no per-vid carve-out either)" do
      result = handler.call(event:, rest: "analyze ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_search.errors.invalid_action")
      expect(result.message_args).to eq(action: "analyze")
    end
  end

  # ── column tweaks (`with` / `without`) still work — inherited mutate_columns ─

  describe "column tweaks still work (inherited mutate_columns)" do
    it "`with <column>` rebuilds the list with the added column" do
      # "views" is a real column token, confirmed present in the vocabulary.
      expect(Pito::MessageBuilder::Video::ListColumns.vocabulary).to include("views" => :views)

      result = handler.call(event:, rest: "with views", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to include("views")
      expect(result.payload["reply_target"]).to eq("video_search")
    end
  end

  # ── per-vid delegation still works — inherited ToolDelegator dispatch ───────

  describe "per-vid delegation still works (inherited ToolDelegator)" do
    it "delegates `show <id>` to the video verb handler: bare detail card, source consumed" do
      result = handler.call(event:, rest: "show ##{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(true)

      detail = result.events.find { |e| e[:kind] == :system }[:payload]
      expect(detail["body"]).to include("Boss Rush")
      expect(detail["reply_target"]).to eq("video_detail")
      expect(detail["video_id"]).to eq(video.id)
    end
  end
end
