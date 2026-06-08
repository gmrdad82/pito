# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::ListColumns do
  # ── vocabulary ──────────────────────────────────────────────────────────────

  describe ".vocabulary" do
    subject(:vocab) { described_class.vocabulary }

    it "returns a Hash" do
      expect(vocab).to be_a(Hash)
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

  # ── headings ────────────────────────────────────────────────────────────────

  describe ".headings" do
    it "returns an empty array for no columns" do
      expect(described_class.headings([])).to eq([])
    end

    it "returns the heading for a single column" do
      expect(described_class.headings([ :duration ])).to eq([ "Duration" ])
    end

    it "returns headings in the requested order" do
      expect(described_class.headings([ :views, :likes ])).to eq([ "Views", "Likes" ])
    end

    it "includes all five headings when all columns are requested" do
      all = %i[game duration views likes comments]
      expect(described_class.headings(all)).to eq(
        [ "Game", "Duration", "Views", "Likes", "Comments" ]
      )
    end
  end

  # ── cells ────────────────────────────────────────────────────────────────────

  describe ".cells" do
    let(:channel) { create(:channel, title: "Test Channel") }
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

    it "returns cells with text-fg-dim class" do
      result = described_class.cells(video, [ :duration ])
      expect(result.first[:class]).to eq("text-fg-dim")
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
