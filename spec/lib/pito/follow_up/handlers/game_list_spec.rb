# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameList do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }

  # A game_list source event whose only row is `game` (#id in the first cell).
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "game_list",
      "table_rows"   => [ { cells: [ { text: "##{game.id}" }, { text: game.title } ] } ]
    })
  end

  it "registers for the game_list target" do
    expect(described_class.target).to eq("game_list")
  end

  it "Matrix serves :append mode for game_list" do
    expect(Pito::Dispatch::Matrix.mode_for("game_list")).to eq(:append)
  end

  it "delegates `show <id>` to the verb handler: bare → the detail card only" do
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)

    # Bare show → detail only (plan-0.9.5 D3; `show <id> full` restores the rest).
    expect(result.events.map { |e| e[:kind] }).to eq([ :system ])
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["body"]).to include("Lies of P")
    expect(detail["reply_target"]).to eq("game_detail")
  end

  it "resolves `show <id>` by GAME id (not video) — reply_target fixes entity type" do
    # Even without the 'game' noun in rest, the entity type is GAME
    # because reply_target = 'game_list' does not start with 'video', so
    # video_target? returns false and the Show handler takes the game branch.
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["game_id"]).to eq(game.id)
    expect(detail["reply_target"]).to eq("game_detail")
  end

  it "returns not-found for a title ref (show is id-only — no title lookup)" do
    result = handler.call(event:, rest: "show lies of p", conversation:)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["game_id"]).to be_nil
  end

  it "appends a witty not-found for an unknown reference" do
    result = handler.call(event:, rest: "show 9999", conversation:)
    expect(result.events.first[:payload]["text"]).to include("9999")
  end

  it "rejects an invalid action (not in the game_list matrix)" do
    result = handler.call(event:, rest: "destroy 5", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Error)
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:ai_event) { instance_double(Event, id: 4242, payload: event.payload) }

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this list" do
      result = handler.call(event: ai_event, rest: "@ai which of these is worth my time", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("which of these is worth my time")
      expect(pending[:payload]["anchor_event_id"]).to eq(4242)
    end
  end

  it "delegates `delete <id>` to the same delete confirmation" do
    result = handler.call(event:, rest: "delete ##{game.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("game_delete")
    expect(ev[:payload]["game_id"]).to eq(game.id)
  end

  it "accepts `rm <id>` as an alias for delete" do
    result = handler.call(event:, rest: "rm ##{game.id}", conversation:)
    expect(result.events.first[:kind].to_s).to eq("confirmation")
  end

  it "stamps game_id in the delete confirmation payload" do
    result = handler.call(event:, rest: "rm ##{game.id}", conversation:)
    expect(result.events.first[:payload]["game_id"]).to eq(game.id)
  end

  it "stamps game_id in the appended detail event payload" do
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    expect(result.events.first[:payload]["game_id"]).to eq(game.id)
  end

  # ── shinies (delegated to Chat::Handlers::Shinies via ToolDelegator) ───────────

  describe "#call — shinies" do
    it "returns a Result::Append with the shinies message for the referenced game" do
      result = handler.call(event:, rest: "shinies ##{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["game_id"]).to eq(game.id)
    end

    it "does NOT return an invalid_action error (shinies is now a declared action)" do
      result = handler.call(event:, rest: "shinies ##{game.id}", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
  end

  # ── price (retired standalone tool, Q16/Q16b — `update` owns field writes) ──

  it "rejects `price` as an invalid_action (retired, no longer a declared action)" do
    result = handler.call(event:, rest: "price set #{game.id} 59.99", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Error)
    expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
  end

  # ── link / unlink (source: game, target: video) ─────────────────────────────

  context "link and unlink verbs (source: game, target: video)" do
    let(:channel) { create(:channel) }
    let!(:video)  { create(:video, :public, title: "Boss Rush", channel:) }

    # The outer `event` has reply_target: "game_list" and no singular game_id
    # in its payload, which correctly signals the list context to follow_up_multi.

    it "link <game_id> to <video_id> creates a VideoGameLink and returns an Append" do
      result = handler.call(event:, rest: "link #{game.id} to #{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(true)
    end

    it "link result has consume: false so the list card stays reusable" do
      result = handler.call(event:, rest: "link #{game.id} to #{video.id}", conversation:)
      expect(result.consume).to be(false)
    end

    it "link <game_id> to <v1>,<v2> creates both VideoGameLinks (multi-target)" do
      channel2 = create(:channel)
      video2   = create(:video, :public, title: "Elden Ring LP", channel: channel2)
      result   = handler.call(event:, rest: "link #{game.id} to #{video.id},#{video2.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(true)
      expect(VideoGameLink.exists?(video: video2, game: game)).to be(true)
    end

    it "unlink <game_id> from <video_id> destroys the VideoGameLink and returns an Append" do
      VideoGameLink.create!(video: video, game: game)
      result = handler.call(event:, rest: "unlink #{game.id} from #{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(VideoGameLink.exists?(video: video, game: game)).to be(false)
    end

    it "unlink result has consume: false so the list card stays reusable" do
      VideoGameLink.create!(video: video, game: game)
      result = handler.call(event:, rest: "unlink #{game.id} from #{video.id}", conversation:)
      expect(result.consume).to be(false)
    end
  end

  # ── `next` pagination ────────────────────────────────────────────────────────
  # Stub page_size to 2 so we can use tiny fixtures.

  # #12 — a reply `sort by` mutation must fold the new sort into the pager cursor
  # so `next`/`more` keeps paging in that order on later pages.
  describe "reply sort folds into the pager cursor (#12)" do
    let!(:sg1) { create(:game, title: "Zeta") }
    let!(:sg2) { create(:game, title: "Alpha") }

    let(:cursor_event) do
      instance_double(Event, kind: "system", payload: {
        "reply_target" => "game_list",
        "game_ids"     => [ sg1.id, sg2.id ],
        "list_columns" => [],
        "list_cursor"  => {
          "offset" => 2, "raw" => "list games", "channel" => nil,
          "sort_token" => nil, "sort_direction" => nil, "columns" => []
        }
      })
    end

    it "writes the new sort_token + direction into list_cursor" do
      result = handler.call(event: cursor_event, rest: "sort by title", conversation:)
      cursor = result.payload["list_cursor"]
      expect(cursor["sort_token"]).to eq("title")
      expect(cursor["sort_direction"]).to eq("asc")
    end

    it "records desc direction from `sort by title desc`" do
      result = handler.call(event: cursor_event, rest: "sort by title desc", conversation:)
      expect(result.payload["list_cursor"]["sort_direction"]).to eq("desc")
    end
  end

  # #8 — search results page a stored similarity ranking (ranked_ids), not a
  # replayed list query.
  describe "search pagination via ranked_ids cursor (#8)" do
    let!(:rg1) { create(:game, title: "Alpha") }
    let!(:rg2) { create(:game, title: "Beta") }
    let!(:rg3) { create(:game, title: "Gamma") }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :list)
        .and_return({ page_size: 2, more_tool: "next" })
    end

    let(:ranked_cursor_event) do
      instance_double(Event, payload: {
        "reply_target" => "game_list",
        "list_cursor"  => {
          "offset"         => 2,
          "ranked_ids"     => [ rg1.id, rg2.id, rg3.id ],
          "columns"        => [],
          "sort_token"     => nil,
          "sort_direction" => nil
        }
      })
    end

    it "pages the stored ranking (offset 2 → the 3rd game) preserving order" do
      result = handler.call(event: ranked_cursor_event, rest: "next", conversation:)
      expect(result.events.first[:payload]["game_ids"]).to eq([ rg3.id ])
    end

    it "carries the cursor's owning tool forward so page 3+ still pages at the owning tool's size, not :list's" do
      rg4 = create(:game, title: "Delta")
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :search)
        .and_return({ page_size: 2, more_tool: "next" })
      multi_page_event = instance_double(Event, payload: {
        "reply_target" => "game_list",
        "list_cursor"  => {
          "offset"         => 0,
          "ranked_ids"     => [ rg1.id, rg2.id, rg3.id, rg4.id ],
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

  describe "`next` pagination" do
    let(:pager_stub) { { page_size: 2, more_tool: "next" } }
    let!(:g1) { create(:game, title: "Alpha") }
    let!(:g2) { create(:game, title: "Beta") }
    let!(:g3) { create(:game, title: "Gamma") }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager)
        .with(tool: :list)
        .and_return(pager_stub)
    end

    # A cursor that was stamped after showing 2 of 3 games (offset = 2).
    let(:cursor_event) do
      instance_double(Event, payload: {
        "reply_target" => "game_list",
        "list_cursor"  => {
          "offset"         => 2,
          "raw"            => "list games",
          "channel"        => nil,
          "sort_token"     => nil,
          "sort_direction" => nil,
          "columns"        => []
        }
      })
    end

    it "renders the final batch with consume: false (no more rows after it)" do
      result = handler.call(event: cursor_event, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      # 1 row left (g3). No more_text — this IS the final batch.
      expect(result.events.first[:payload]["list_cursor"]).to be_nil
    end

    it "final batch has no list_more footer fragment" do
      result = handler.call(event: cursor_event, rest: "next", conversation:)
      footer = result.events.first[:payload]["list_footer"].to_s
      # No %{total}/%{rest} copy — it's the last page, list_more is not appended.
      expect(footer).not_to include("next")
    end

    # The outer `let!(:game)` fixture adds 1 game on top of g1..g5, giving 6
    # total. With page_size=2 and offset=2: shown = 4, rest = 6 - 4 = 2.
    context "mid-batch (6 games: outer game + g1..g5, page_size=2, offset=2)" do
      let!(:g4) { create(:game, title: "Delta") }
      let!(:g5) { create(:game, title: "Epsilon") }

      let(:mid_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "game_list",
          "list_cursor"  => {
            "offset"         => 2,
            "raw"            => "list games",
            "channel"        => nil,
            "sort_token"     => nil,
            "sort_direction" => nil,
            "columns"        => []
          }
        })
      end

      it "list_footer for a mid-batch `next` contains count (2) and total (6)" do
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        # Variant 0: "%{count} rows out of %{total}. `%{tool}` for more."
        expect(footer).to include("2")
        expect(footer).to include("6")
      end

      it "rest = total − (offset + rows.size) = 2 is passed to Copy.render" do
        # Force variant 1 which uses %{rest}: "%{count} here, %{rest} more in the system. `%{tool}`."
        Pito::Copy.sampler = ->(entries) { entries[1] }
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        # count=2, rest=2 → "2 here, 2 more in the system. `next`."
        expect(footer).to include("2 more in the system")
      end
    end

    context "no cursor (completed list)" do
      let(:no_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "game_list"
          # no list_cursor key
        })
      end

      it "renders list_end copy" do
        result = handler.call(event: no_cursor_event, rest: "next", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        text = result.events.first[:payload]["text"].to_s
        expect(text).to be_present
        # The list_end copy does NOT contain "next" (it's not a list_more variant).
        expect(text).not_to match(/%\{/)
      end
    end

    # A single-channel list's page-1 suppression must survive into every later
    # page — never re-derived per page, never re-offering/re-adding :channels.
    context "single-channel suppression inherited from the cursor" do
      let(:suppressed_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "game_list",
          "list_cursor"  => {
            "offset"             => 2,
            "raw"                => "list games",
            "channel"            => nil,
            "sort_token"         => nil,
            "sort_direction"     => nil,
            "columns"            => [ "genre" ],
            "suppressed_columns" => [ "channels" ]
          }
        })
      end

      it "carries suppressed_columns forward onto the next page's payload" do
        result = handler.call(event: suppressed_cursor_event, rest: "next", conversation:)
        expect(result.events.first[:payload]["suppressed_columns"]).to eq([ "channels" ])
      end

      it "excludes channel from the next page's options footer" do
        result = handler.call(event: suppressed_cursor_event, rest: "next", conversation:)
        expect(result.events.first[:payload]["list_footer"]).not_to include("channel")
      end
    end
  end
end
