# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::ListColumns do
  include ActiveSupport::Testing::TimeHelpers

  # ── vocabulary ──────────────────────────────────────────────────────────────

  describe ".vocabulary" do
    subject(:vocab) { described_class.vocabulary }

    it "returns a Hash" do
      expect(vocab).to be_a(Hash)
    end

    it "maps 'channel' to :channel" do
      expect(vocab["channel"]).to eq(:channel)
    end

    it "maps 'visibility' to :visibility" do
      expect(vocab["visibility"]).to eq(:visibility)
    end

    it "maps 'status' to :visibility (status is a functional alias)" do
      expect(vocab["status"]).to eq(:visibility)
    end

    it "maps 'game' to :game" do
      expect(vocab["game"]).to eq(:game)
    end

    it "maps 'category' AND 'categories' to :category (E1 — vid category column)" do
      expect(vocab["category"]).to eq(:category)
      expect(vocab["categories"]).to eq(:category)
    end

    it "maps 'games' to :game" do
      expect(vocab["games"]).to eq(:game)
    end

    it "maps 'duration' to :duration" do
      expect(vocab["duration"]).to eq(:duration)
    end

    # G26.3 — 'length' stays accepted as a silent backward-compat alias.
    it "maps 'length' to :duration (backward-compat alias, G26.3)" do
      expect(vocab["length"]).to eq(:duration)
    end

    it "maps 'views' to :views" do
      expect(vocab["views"]).to eq(:views)
    end

    it "maps 'likes' to :likes" do
      expect(vocab["likes"]).to eq(:likes)
    end

    # G26.1 — comments column removed; 'comments' / 'comms' no longer map to anything.
    it "does not map 'comments' (column removed, G26.1)" do
      expect(vocab["comments"]).to be_nil
    end

    it "does not map 'comms' (column removed, G26.1)" do
      expect(vocab["comms"]).to be_nil
    end

    it "does not include unknown tokens" do
      expect(vocab.key?("unknown_token")).to be(false)
    end
  end

  # ── base_sort_tokens ─────────────────────────────────────────────────────────

  describe ".base_sort_tokens" do
    it "returns id and title only" do
      expect(described_class.base_sort_tokens).to eq(%w[id title])
    end
  end

  # ── headings ────────────────────────────────────────────────────────────────

  describe ".headings" do
    it "returns an empty array for no columns" do
      expect(described_class.headings([])).to eq([])
    end

    it "returns the heading for :channel" do
      expect(described_class.headings([ :channel ])).to eq([ "Channel" ])
    end

    it "returns the heading for :visibility (from copy, 'Visibility')" do
      expect(described_class.headings([ :visibility ])).to eq([ "Visibility" ])
    end

    it "returns Channel and Visibility in order" do
      expect(described_class.headings([ :channel, :visibility ])).to eq([ "Channel", "Visibility" ])
    end

    # G26.3 — canonical heading is now "Duration" (was "Length").
    it "returns the heading for a single column" do
      expect(described_class.headings([ :duration ])).to eq([ "Duration" ])
    end

    it "returns headings in the requested order" do
      expect(described_class.headings([ :views, :likes ])).to eq([ "Views", "Likes" ])
    end

    # G26.1 — :comments removed; G26.3 — heading is "Duration" not "Length".
    it "includes headings for the remaining stats columns (no comments, G26.1)" do
      cols = %i[game duration views likes]
      expect(described_class.headings(cols)).to eq(
        [ "Game", "Duration", "Views", "Likes" ]
      )
    end
  end

  # ── heading_cells ─────────────────────────────────────────────────────────────

  describe ".heading_cells" do
    it "tags a left-aligned added column with the cyan --added class" do
      expect(described_class.heading_cells([ :channel ])).to eq(
        [ { "text" => "Channel", "class" => "pito-table-heading--added" } ]
      )
    end

    # G26.3 — heading is "Duration" (was "Length").
    it "right-aligns and tags the :duration heading" do
      expect(described_class.heading_cells([ :duration ])).to eq(
        [ { "text" => "Duration", "class" => "pito-table-heading--added text-right" } ]
      )
    end

    it "tags both added headings, in order" do
      expect(described_class.heading_cells([ :channel, :duration ])).to eq(
        [
          { "text" => "Channel", "class" => "pito-table-heading--added" },
          { "text" => "Duration", "class" => "pito-table-heading--added text-right" }
        ]
      )
    end
  end

  # ── options_footer ───────────────────────────────────────────────────────────

  describe ".options_footer" do
    # G26.1 — comms/comments column removed; "comms" must no longer appear in the footer.
    it "names the still-addable columns when some remain (no comms, G26.1)" do
      footer = described_class.options_footer([ :channel ])
      expect(footer).to include("views")
      expect(footer).not_to include("comms")
    end

    it "renders 'nothing' on the addable side when every optional column is visible" do
      footer = described_class.options_footer(described_class::COLUMNS.keys)
      expect(footer).to include("nothing")
    end

    it "includes the sort key for the visible optional column" do
      footer = described_class.options_footer([ :channel ])
      expect(footer).to include("channel")
      expect(footer).to include("id")
      expect(footer).to include("title")
    end
  end

  # ── sort_key_for ─────────────────────────────────────────────────────────────

  describe ".sort_key_for" do
    let(:chan) { create(:channel, handle: "@test") }
    let(:vid)  { create(:video, :public, title: "Test Video", channel: chan) }

    it "returns a proc for a base column regardless of selected_columns" do
      key = described_class.sort_key_for("title", selected_columns: [])
      expect(key).to be_a(Proc)
      expect(key.call(vid)).to eq("test video")
    end

    it "returns nil for 'channel' when :channel is not in selected_columns" do
      key = described_class.sort_key_for("channel", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'channel' when :channel is in selected_columns" do
      key = described_class.sort_key_for("channel", selected_columns: [ :channel ])
      expect(key).to be_a(Proc)
    end

    it "returns nil for the dropped 'privacy' token" do
      key = described_class.sort_key_for("privacy", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns nil for 'visibility' when :visibility is not in selected_columns" do
      key = described_class.sort_key_for("visibility", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'visibility' when :visibility is in selected_columns" do
      key = described_class.sort_key_for("visibility", selected_columns: [ :visibility ])
      expect(key).to be_a(Proc)
    end

    it "returns nil for a with-column NOT in selected_columns" do
      key = described_class.sort_key_for("views", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for a with-column that IS in selected_columns" do
      key = described_class.sort_key_for("views", selected_columns: [ :views ])
      expect(key).to be_a(Proc)
    end

    it "returns nil for an unknown token" do
      key = described_class.sort_key_for("bogus", selected_columns: [ :views ])
      expect(key).to be_nil
    end

    it "returns nil for 'game' with-column NOT in selected_columns" do
      key = described_class.sort_key_for("game", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns nil for 'handle' alias when :channel is not in selected_columns" do
      key = described_class.sort_key_for("handle", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'handle' alias when :channel is in selected_columns" do
      key = described_class.sort_key_for("handle", selected_columns: [ :channel ])
      expect(key).to be_a(Proc)
    end

    it "is case-insensitive for the token" do
      key = described_class.sort_key_for("TITLE", selected_columns: [])
      expect(key).to be_a(Proc)
    end

    # G26.3 — both 'duration' (canonical) and 'length' (backward-compat alias) must
    # resolve to the same sort proc when :duration is in selected_columns.
    it "returns nil for 'duration' when :duration is not in selected_columns" do
      key = described_class.sort_key_for("duration", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'duration' when :duration IS in selected_columns" do
      key = described_class.sort_key_for("duration", selected_columns: [ :duration ])
      expect(key).to be_a(Proc)
    end

    it "returns a proc for 'length' (alias) when :duration IS in selected_columns (G26.3)" do
      key = described_class.sort_key_for("length", selected_columns: [ :duration ])
      expect(key).to be_a(Proc)
      expect(key.call(vid)).to eq(vid.duration_seconds.to_i)
    end

    it "returns nil for 'length' alias when :duration is not in selected_columns" do
      key = described_class.sort_key_for("length", selected_columns: [])
      expect(key).to be_nil
    end
  end

  # ── cells ────────────────────────────────────────────────────────────────────

  describe ".cells" do
    let(:channel) { create(:channel, title: "Test Channel", handle: "mychannel") }
    let(:game)    { create(:game, title: "Elden Ring") }

    let(:video) do
      v = create(:video, :public, channel: channel, title: "Test Video",
                                  duration_seconds: 574)
      create(:video_game_link, video: v, game: game)
      create(:stat, entity: v, kind: "views",    value: 10_000)
      create(:stat, entity: v, kind: "likes",    value: 500)
      create(:stat, entity: v, kind: "comments", value: 42)
      v.reload
    end

    it "returns an empty array for no columns" do
      expect(described_class.cells(video, [])).to eq([])
    end

    it "returns cells with the game cap/truncate class" do
      result = described_class.cells(video, [ :game ])
      expect(result.first[:class]).to eq("text-fg-dim pito-cell-game")
    end

    it "right-aligns and clamps the :duration cell (tabular + pito-cell-duration)" do
      result = described_class.cells(video, [ :duration ])
      expect(result.first[:class]).to eq("text-fg-dim text-right tabular-nums pito-cell-duration")
    end

    it "renders the human category name for :category (E1)" do
      video.update!(category_id: "20") # → Gaming
      expect(described_class.cells(video, [ :category ]).first[:text]).to eq("Gaming")
    end

    it "renders an em-dash for :category when the video has no category" do
      video.update!(category_id: nil)
      expect(described_class.cells(video, [ :category ]).first[:text]).to eq("—")
    end

    it "returns the channel at-handle for :channel" do
      result = described_class.cells(video, [ :channel ])
      expect(result.first[:text]).to eq("@mychannel")
    end

    it "applies shimmer and clamps the :channel cell (pito-token + pito-cell-channel)" do
      result = described_class.cells(video, [ :channel ])
      expect(result.first[:class]).to include("pito-token")
      expect(result.first[:class]).to include("pito-cell-channel")
      expect(result.first[:class]).not_to include("text-cyan")
    end

    it "renders the channel @handle as a PLAIN token across rows (no shimmer offset — owner 17.4)" do
      video2  = create(:video, :public, channel: channel, title: "Another Video on Same Channel")
      result1 = described_class.cells(video,  [ :channel ])
      result2 = described_class.cells(video2, [ :channel ])

      # Both videos share the same channel, so the handle text is identical.
      expect(result1.first[:text]).to eq(result2.first[:text])

      # Decorative handles are plain now — no shimmer, hence no per-row offset.
      [ result1, result2 ].each do |r|
        expect(r.first[:class]).to include("pito-token")
        expect(r.first[:class]).not_to match(/\bpito-shimmer-d\d+\b/)
      end
    end

    it "returns the visibility label for :visibility" do
      result = described_class.cells(video, [ :visibility ])
      expect(result.first[:text]).to eq("Public")
    end

    it "returns channel and visibility cells in order" do
      result = described_class.cells(video, [ :channel, :visibility ])
      expect(result.map { |c| c[:text] }).to eq([ "@mychannel", "Public" ])
    end

    it "renders the linked game as '#id title' (html cell) for :game" do
      result = described_class.cells(video, [ :game ])
      cell   = result.first
      expect(cell[:html]).to be(true)
      expect(cell[:text]).to include("##{game.id}")
      expect(cell[:text]).to include("Elden Ring")
    end

    it "makes the game #id a yellow kbd shimmer token that opens 'show game #id' (clickable)" do
      cell = described_class.cells(video, [ :game ]).first
      expect(cell[:text]).to include("pito-action-shimmer")
      expect(cell[:text]).to include("show game ##{game.id}")
      expect(cell[:text]).to include("pito--chat-prefill")
    end

    it "renders '—' for :game when the video has no linked games" do
      bare = create(:video, :public, channel: channel, title: "No Game")
      cell = described_class.cells(bare, [ :game ]).first
      expect(cell[:text]).to eq("—")
    end

    it "returns the formatted duration for :duration" do
      result = described_class.cells(video, [ :duration ])
      expect(result.first[:text]).to eq("9:34")
    end

    it "returns '—' for nil duration" do
      no_dur = create(:video, :public, channel: channel, title: "No Duration Video",
                                       duration_seconds: nil)
      result = described_class.cells(no_dur, [ :duration ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns the view count as a string for :views" do
      result = described_class.cells(video, [ :views ])
      expect(result.first[:text]).to eq("10000")
    end

    it "returns the like count as a string for :likes" do
      result = described_class.cells(video, [ :likes ])
      expect(result.first[:text]).to eq("500")
    end

    it "returns '—' for nil view count" do
      no_stats = create(:video, :public, channel: channel, title: "No Stats Video")
      result   = described_class.cells(no_stats, [ :views ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns '—' for nil like count" do
      no_stats = create(:video, :public, channel: channel, title: "No Likes Video")
      result   = described_class.cells(no_stats, [ :likes ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns cells in the requested column order" do
      result = described_class.cells(video, [ :views, :likes ])
      expect(result.size).to eq(2)
      expect(result[0][:text]).to eq("10000")
      expect(result[1][:text]).to eq("500")
    end
  end

  # The slate's :scheduled column is internal — it renders when passed explicitly,
  # but is invisible to the with/without/sort vocabulary + options footer, so
  # `list videos` and its column levers are unchanged.
  describe "internal :scheduled column" do
    it "renders the go-live time via cells when passed explicitly" do
      travel_to(Time.zone.local(2026, 3, 1, 10, 0)) do
        v = create(:video, :public, channel: create(:channel), title: "Sched", publish_at: Time.zone.local(2026, 3, 1, 13, 0))
        cell = described_class.cells(v, [ :scheduled ]).first
        expect(cell[:text]).to eq("in 3 hours")
      end
    end

    it "is NOT in the with/without vocabulary" do
      expect(described_class.vocabulary).not_to have_key("scheduled")
    end

    it "is NOT offered as an addable column in the options footer" do
      footer = described_class.options_footer([]).to_s
      expect(footer).not_to include("scheduled")
    end

    it "is NOT offered as removable even when shown" do
      footer = described_class.options_footer([ :scheduled ]).to_s
      expect(footer).not_to include("scheduled")
    end
  end

  # U6 — publish_at is the PUBLIC, sortable counterpart to the internal :scheduled
  # column: a bare "DD-MM-YYYY HH:MM" go-live timestamp, split out of the
  # visibility scope so it is a first-class with/sort column (and MCP field).
  describe "public :publish_at column (U6)" do
    let(:channel) { create(:channel, handle: "@ch") }

    it "maps 'publish_at' and the 'publish' alias to :publish_at in the vocabulary" do
      expect(described_class.vocabulary["publish_at"]).to eq(:publish_at)
      expect(described_class.vocabulary["publish"]).to eq(:publish_at)
    end

    it "IS offered as an addable column in the options footer (unlike :scheduled)" do
      footer = described_class.options_footer([]).to_s
      expect(footer).to include("publish_at")
    end

    it "returns nil for 'publish_at' sort when :publish_at is not in selected_columns" do
      expect(described_class.sort_key_for("publish_at", selected_columns: [])).to be_nil
    end

    it "sorts by go-live epoch when :publish_at is selected (nil sorts as 0)" do
      key   = described_class.sort_key_for("publish_at", selected_columns: [ :publish_at ])
      sched = create(:video, :scheduled, channel: channel, title: "Sched")
      live  = create(:video, :public, channel: channel, title: "Live")
      expect(key).to be_a(Proc)
      expect(key.call(sched)).to eq(sched.publish_at.to_i)
      expect(key.call(live)).to eq(0)
    end

    it "sorts a stale past publish_at into the same 0 bucket as nil, both before a future one" do
      key    = described_class.sort_key_for("publish_at", selected_columns: [ :publish_at ])
      future = create(:video, :scheduled, channel: channel, title: "Future")
      past   = create(:video, :public, channel: channel, title: "Past", publish_at: 1.day.ago)
      nilpa  = create(:video, :public, channel: channel, title: "NilPA")

      expect(key.call(past)).to eq(0)
      expect(key.call(nilpa)).to eq(0)
      expect(key.call(future)).to eq(future.publish_at.to_i)
    end

    it "renders the bare SyncStamp timestamp for a scheduled vid" do
      travel_to(Time.zone.local(2026, 3, 1, 10, 0)) do
        v    = create(:video, :public, channel: channel, title: "Sched", publish_at: Time.zone.local(2026, 3, 1, 13, 0))
        cell = described_class.cells(v, [ :publish_at ]).first
        expect(cell[:text]).to eq("01-03-2026 13:00")
      end
    end

    it "renders '—' for a vid with no publish_at" do
      v    = create(:video, :public, channel: channel, title: "Live", publish_at: nil)
      cell = described_class.cells(v, [ :publish_at ]).first
      expect(cell[:text]).to eq("—")
    end

    it "renders '—' (not the timestamp) for a vid with a stale past publish_at" do
      v    = create(:video, :public, channel: channel, title: "Stale", publish_at: 1.day.ago)
      cell = described_class.cells(v, [ :publish_at ]).first
      expect(cell[:text]).to eq("—")
    end
  end
end
