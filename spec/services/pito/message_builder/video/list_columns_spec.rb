# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::ListColumns do
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

    it "maps 'game' to :game" do
      expect(vocab["game"]).to eq(:game)
    end

    it "maps 'games' to :game" do
      expect(vocab["games"]).to eq(:game)
    end

    it "maps 'duration' to :duration" do
      expect(vocab["duration"]).to eq(:duration)
    end

    it "maps 'views' to :views" do
      expect(vocab["views"]).to eq(:views)
    end

    it "maps 'likes' to :likes" do
      expect(vocab["likes"]).to eq(:likes)
    end

    it "maps 'comments' to :comments" do
      expect(vocab["comments"]).to eq(:comments)
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

    it "returns the heading for :visibility (from copy, now 'Status')" do
      expect(described_class.headings([ :visibility ])).to eq([ "Status" ])
    end

    it "returns Channel and Status in order" do
      expect(described_class.headings([ :channel, :visibility ])).to eq([ "Channel", "Status" ])
    end

    it "returns the heading for a single column" do
      expect(described_class.headings([ :duration ])).to eq([ "Length" ])
    end

    it "returns headings in the requested order" do
      expect(described_class.headings([ :views, :likes ])).to eq([ "Views", "Likes" ])
    end

    it "includes headings for the stats columns" do
      cols = %i[game duration views likes comments]
      expect(described_class.headings(cols)).to eq(
        [ "Game", "Length", "Views", "Likes", "Comments" ]
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

    it "right-aligns and tags the :duration heading" do
      expect(described_class.heading_cells([ :duration ])).to eq(
        [ { "text" => "Length", "class" => "pito-table-heading--added text-right" } ]
      )
    end

    it "tags both added headings, in order" do
      expect(described_class.heading_cells([ :channel, :duration ])).to eq(
        [
          { "text" => "Channel", "class" => "pito-table-heading--added" },
          { "text" => "Length", "class" => "pito-table-heading--added text-right" }
        ]
      )
    end
  end

  describe ".addable_footer" do
    it "names the still-addable columns when some remain" do
      footer = described_class.addable_footer([ :channel ])
      expect(footer).to include("views")
      expect(footer).to include("comments")
    end

    it "uses the all-shown variant (no column names) when every column is present" do
      footer = described_class.addable_footer(described_class::COLUMNS.keys)
      expect(footer).not_to include("views")
      expect(footer).not_to include("channel")
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

    it "returns the channel at-handle for :channel" do
      result = described_class.cells(video, [ :channel ])
      expect(result.first[:text]).to eq("@mychannel")
    end

    it "colors and clamps the :channel cell (cyan + pito-cell-channel)" do
      result = described_class.cells(video, [ :channel ])
      expect(result.first[:class]).to eq("text-cyan pito-cell-channel")
    end

    it "returns the visibility label for :visibility" do
      result = described_class.cells(video, [ :visibility ])
      expect(result.first[:text]).to eq("Public")
    end

    it "returns channel and visibility cells in order" do
      result = described_class.cells(video, [ :channel, :visibility ])
      expect(result.map { |c| c[:text] }).to eq([ "@mychannel", "Public" ])
    end

    it "returns the linked game title for :game" do
      result = described_class.cells(video, [ :game ])
      expect(result.first[:text]).to include("Elden Ring")
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

    it "returns the comment count as a string for :comments" do
      result = described_class.cells(video, [ :comments ])
      expect(result.first[:text]).to eq("42")
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

    it "returns '—' for nil comment count" do
      no_stats = create(:video, :public, channel: channel, title: "No Comments Video")
      result   = described_class.cells(no_stats, [ :comments ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns cells in the requested column order" do
      result = described_class.cells(video, [ :views, :likes ])
      expect(result.size).to eq(2)
      expect(result[0][:text]).to eq("10000")
      expect(result[1][:text]).to eq("500")
    end
  end
end
