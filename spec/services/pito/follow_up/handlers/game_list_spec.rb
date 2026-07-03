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

  # ── shinies (delegated to Chat::Handlers::Shinies via VerbDelegator) ───────────

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

  # ── price (delegated to Chat::Handlers::Price via VerbDelegator) ───────────────

  describe "#call — price" do
    it "sets the referenced game's price from a list reply (#<handle> price set <id> <amount>)" do
      result = handler.call(event:, rest: "price set #{game.id} 59.99", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(game.reload.price).to eq(BigDecimal("59.99"))
    end

    it "sets an explicit 0 (free) from a list reply" do
      handler.call(event:, rest: "price set #{game.id} 0", conversation:)
      expect(game.reload.price).to eq(0)
    end

    it "does NOT return an invalid_action error (price is now a declared action)" do
      result = handler.call(event:, rest: "price set #{game.id} 9.99", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
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

  describe "`next` pagination" do
    let(:pager_stub) { { page_size: 2, more_verb: "next" } }
    let!(:g1) { create(:game, title: "Alpha") }
    let!(:g2) { create(:game, title: "Beta") }
    let!(:g3) { create(:game, title: "Gamma") }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager)
        .with(verb: :list)
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
        # Variant 0: "%{count} rows out of %{total}. `%{verb}` for more."
        expect(footer).to include("2")
        expect(footer).to include("6")
      end

      it "rest = total − (offset + rows.size) = 2 is passed to Copy.render" do
        # Force variant 1 which uses %{rest}: "%{count} here, %{rest} more in the system. `%{verb}`."
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
  end
end
