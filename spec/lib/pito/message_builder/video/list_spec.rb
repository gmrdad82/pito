# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::List do
  let(:conversation) { create(:conversation) }
  let(:channel)      { create(:channel, title: "Test Channel") }
  let!(:video1) do
    create(:video, :public, channel: channel, title: "Alpha Video")
  end
  let!(:video2) do
    create(:video, :private, channel: channel, title: "Beta Video")
  end

  describe ".call" do
    let(:videos) { ::Video.where(id: [ video1.id, video2.id ]).order(:title) }

    subject(:payload) { described_class.call(videos, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "wraps the intro count in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">2</span>})
    end

    it "wraps the vids noun in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">vids</span>})
    end

    context "when there is exactly 1 video" do
      let(:videos) { ::Video.where(id: video1.id) }

      it "uses the singular noun 'vid'" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">vid</span>})
      end

      it "does not use the plural noun 'vids'" do
        expect(payload["body"]).not_to match(%r{<span class="pito-subject-shimmer[^"]*">vids</span>})
      end
    end

    it "has table_rows with one entry per video" do
      expect(payload["table_rows"]).to be_present
      expect(payload["table_rows"].size).to eq(2)
    end

    it "sets html true so the shimmer intro reveals via the htmlProse path" do
      expect(payload["html"]).to be true
    end

    it "each row uses the cells format with 2 cells" do
      payload["table_rows"].each do |row|
        expect(row[:cells]).to be_an(Array)
        expect(row[:cells].size).to eq(2)
      end
    end

    describe "cell 1 — id" do
      it "prefixes the video id with # and applies shimmer/tabular/right classes" do
        row = payload["table_rows"].first
        cell = row[:cells][0]
        video = videos.first
        expect(cell[:text]).to eq("##{video.id}")
        expect(cell[:class]).to include("pito-action-shimmer")
        expect(cell[:class]).to include("tabular-nums")
        expect(cell[:class]).to include("text-right")
      end

      it "carries chat-prefill data so a click auto-submits `show vid #id` (J5)" do
        cell = payload["table_rows"].first[:cells][0]
        data = cell[:data]
        expect(data[:controller]).to eq("pito--chat-prefill")
        expect(data[:action]).to eq("click->pito--chat-prefill#fill")
        expect(data[:"pito--chat-prefill-text-value"]).to eq("show vid #{cell[:text]}")
        expect(data[:"pito--chat-prefill-submit-value"]).to eq("true")
      end
    end

    describe "cell 2 — title" do
      it "shows the video title with text-fg class" do
        row = payload["table_rows"].first
        cell = row[:cells][1]
        expect(cell[:text]).to eq(videos.first.title)
        expect(cell[:class]).to include("text-fg")
      end

      it "title cell (index 1) carries the pito-cell-title class" do
        cell = payload["table_rows"].first[:cells][1]
        expect(cell[:class]).to include("pito-cell-title")
        expect(cell[:class]).to include("text-fg")
      end
    end

    it "includes table_heading with # and Title only" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Title" ])
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    it "payload includes list_footer as a String" do
      expect(payload["list_footer"]).to be_a(String)
    end
  end

  describe ".call with columns: [:channel, :visibility]" do
    let(:videos) { ::Video.where(id: [ video1.id, video2.id ]).order(:title) }

    subject(:payload) do
      described_class.call(videos, conversation: conversation,
                           columns: [ :channel, :visibility ])
    end

    it "includes table_heading with #, Title, Channel, Visibility" do
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" }, "Title",
        { "text" => "Channel", "class" => "pito-table-heading--added" },
        { "text" => "Visibility", "class" => "pito-table-heading--added" }
      ])
    end

    it "each row has 4 cells" do
      payload["table_rows"].each do |row|
        expect(row[:cells].size).to eq(4)
      end
    end

    describe "cell 3 — channel handle" do
      it "shows the channel at_handle" do
        row = payload["table_rows"].first
        cell = row[:cells][2]
        expect(cell[:text]).to eq(channel.at_handle)
      end
    end

    describe "cell 4 — visibility label" do
      it "shows 'Public' for a public video" do
        row = payload["table_rows"].find { |r| r[:cells][1][:text] == "Alpha Video" }
        cell = row[:cells][3]
        expect(cell[:text]).to eq("Public")
      end

      it "shows 'Private' for a private video" do
        row = payload["table_rows"].find { |r| r[:cells][1][:text] == "Beta Video" }
        cell = row[:cells][3]
        expect(cell[:text]).to eq("Private")
      end

      it "emits an empty string when privacy_status is blank" do
        blank_video = instance_double(::Video,
                                     id: 99_999,
                                     title: "No Status",
                                     privacy_status: nil,
                                     publish_at: nil,
                                     channel: channel)
        row = described_class.call([ blank_video ], conversation: conversation,
                                   columns: [ :channel, :visibility ])["table_rows"].first
        cell = row[:cells][3]
        expect(cell[:text]).to eq("")
      end
    end
  end

  describe ".call with columns: [:game, :duration]" do
    let(:game) { create(:game, title: "Elden Ring") }

    let!(:video_with_game) do
      v = create(:video, :public, channel: channel, title: "Gamma Video",
                                  duration_seconds: 3742)
      create(:video_game_link, video: v, game: game)
      v.reload
      v
    end

    let(:videos_with_game) { ::Video.where(id: video_with_game.id) }

    subject(:payload_with_cols) do
      described_class.call(videos_with_game, conversation: conversation,
                           columns: [ :game, :duration ])
    end

    it "includes 'Game' and a right-aligned 'Duration' in the table_heading" do
      expect(payload_with_cols["table_heading"]).to eq(
        [
          { "text" => "#", "class" => "text-right" }, "Title",
          { "text" => "Game", "class" => "pito-table-heading--added" },
          { "text" => "Duration", "class" => "pito-table-heading--added text-right" }
        ]
      )
    end

    it "each row has 4 cells" do
      payload_with_cols["table_rows"].each do |row|
        expect(row[:cells].size).to eq(4)
      end
    end

    it "cell 3 contains the linked game title" do
      cell = payload_with_cols["table_rows"].first[:cells][2]
      expect(cell[:text]).to include("Elden Ring")
    end

    it "cell 4 contains the formatted duration" do
      cell = payload_with_cols["table_rows"].first[:cells][3]
      expect(cell[:text]).to eq("1:02:22")
    end

    it "cell 4 is right-aligned, tabular, and clamped" do
      cell = payload_with_cols["table_rows"].first[:cells][3]
      expect(cell[:class]).to eq("text-fg-dim text-right tabular-nums pito-cell-duration")
    end
  end

  # ── Scores (search's `like` path) ────────────────────────────────────────────

  describe ".call with scores:" do
    let(:videos) { ::Video.where(id: [ video1.id, video2.id ]).order(:title) }
    let(:scores) { { video1.id => 91, video2.id => 5 } }

    subject(:payload) { described_class.call(videos, conversation: conversation, scores: scores) }

    it "appends a trailing Similarity heading (raw rescaled cosine, distinct from games' Match)" do
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" },
        "Title",
        "Similarity"
      ])
    end

    it "appends a trailing { score: } cell matching each record's score" do
      row1 = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{video1.id}" }
      row2 = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{video2.id}" }
      expect(row1[:cells].last).to eq({ score: 91 })
      expect(row2[:cells].last).to eq({ score: 5 })
    end

    context "when a record's id is absent from the scores hash" do
      let(:scores) { { video1.id => 91 } }

      it "renders { score: nil } for the record missing from the hash" do
        row2 = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{video2.id}" }
        expect(row2[:cells].last).to eq({ score: nil })
      end
    end
  end

  describe ".call with scores: nil (explicit) — identical to omitting scores" do
    let(:videos) { ::Video.where(id: [ video1.id, video2.id ]).order(:title) }

    subject(:payload) { described_class.call(videos, conversation: conversation, scores: nil) }

    it "does not append a Similarity heading" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Title" ])
    end

    it "does not append a score cell to any row" do
      payload["table_rows"].each do |row|
        expect(row[:cells].size).to eq(2)
      end
    end
  end
end
