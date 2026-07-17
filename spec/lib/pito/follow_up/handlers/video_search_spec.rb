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

  # ── pager (`next` / `more`) pages the ranked_ids cursor, mirroring         ──
  # ── GameList's own ranked_ids branch (#8/#12 parity) ─────────────────────

  describe "pager (`next` / `more`) pages the stored ranking" do
    it "`next` actually routes (no invalid_action error — config now declares it)" do
      result = handler.call(event:, rest: "next", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "with no list_cursor stamped, `next` renders list_end copy, not an error" do
      result = handler.call(event:, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      text = result.events.first[:payload]["text"].to_s
      expect(text).to be_present
      expect(text).not_to match(/%\{/)
    end

    context "with a ranked_ids cursor (search results beyond a page)" do
      let!(:rv1) { create(:video, title: "Alpha") }
      let!(:rv2) { create(:video, title: "Beta") }
      let!(:rv3) { create(:video, title: "Gamma") }

      let(:ranked_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "video_search",
          "list_cursor"  => {
            "offset"         => 2,
            "ranked_ids"     => [ rv1.id, rv2.id, rv3.id ],
            "columns"        => [],
            "sort_token"     => nil,
            "sort_direction" => nil,
            "tool"           => "search"
          }
        })
      end

      before do
        allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
          .and_return({ page_size: 2, more_tool: "next" })
      end

      it "pages the stored ranking (offset 2 → the 3rd vid) preserving order, honoring the cursor's own tool page size" do
        result = handler.call(event: ranked_cursor_event, rest: "next", conversation:)
        expect(result.events.first[:payload]["video_ids"]).to eq([ rv3.id ])
      end

      it "`more` (the next alias) pages identically" do
        result = handler.call(event: ranked_cursor_event, rest: "more", conversation:)
        expect(result.events.first[:payload]["video_ids"]).to eq([ rv3.id ])
      end

      it "the final batch (no rows left after it) has consume: false and no list_cursor" do
        result = handler.call(event: ranked_cursor_event, rest: "next", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(false)
        expect(result.events.first[:payload]["list_cursor"]).to be_nil
      end

      it "page 2+ KEEPS the video_search reply target — sort/analyze never sneak back in via the builder's video_list default" do
        result = handler.call(event: ranked_cursor_event, rest: "next", conversation:)
        expect(result.events.first[:payload]["reply_target"]).to eq("video_search")
      end

      it "carries the cursor's owning tool forward so page 3+ still pages at search's size, not :list's" do
        # The list_more footer names its continuation tool from :list's pager
        # unconditionally — stub it alongside the cursor-owning :search pager.
        allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :list)
          .and_return({ page_size: 50, more_tool: "next" })
        four = create(:video, title: "Delta")
        multi_page_event = instance_double(Event, payload: {
          "reply_target" => "video_search",
          "list_cursor"  => {
            "offset"         => 0,
            "ranked_ids"     => [ rv1.id, rv2.id, rv3.id, four.id ],
            "columns"        => [],
            "sort_token"     => nil,
            "sort_direction" => nil,
            "tool"           => "search"
          }
        })

        result = handler.call(event: multi_page_event, rest: "next", conversation:)
        expect(result.events.first[:payload]["list_cursor"]["tool"]).to eq("search")
      end
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
