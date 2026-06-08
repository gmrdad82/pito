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

    it "has a body with the intro count" do
      expect(payload["body"]).to include("2")
    end

    it "has table_rows with one entry per video" do
      expect(payload["table_rows"]).to be_present
      expect(payload["table_rows"].size).to eq(2)
    end

    it "does not have an html key" do
      expect(payload).not_to have_key("html")
      expect(payload).not_to have_key(:html)
    end

    it "each row uses the cells format with 4 cells" do
      payload["table_rows"].each do |row|
        expect(row[:cells]).to be_an(Array)
        expect(row[:cells].size).to eq(4)
      end
    end

    describe "cell 1 — id" do
      it "prefixes the video id with # and applies cyan/tabular/right classes" do
        row = payload["table_rows"].first
        cell = row[:cells][0]
        video = videos.first
        expect(cell[:text]).to eq("##{video.id}")
        expect(cell[:class]).to include("text-cyan")
        expect(cell[:class]).to include("tabular-nums")
        expect(cell[:class]).to include("text-right")
      end
    end

    describe "cell 2 — title" do
      it "shows the video title with text-fg class" do
        row = payload["table_rows"].first
        cell = row[:cells][1]
        expect(cell[:text]).to eq(videos.first.title)
        expect(cell[:class]).to include("text-fg")
      end
    end

    describe "cell 3 — channel handle" do
      it "shows the channel at_handle with text-cyan class" do
        row = payload["table_rows"].first
        cell = row[:cells][2]
        expect(cell[:text]).to eq(channel.at_handle)
        expect(cell[:class]).to include("text-cyan")
      end
    end

    describe "cell 4 — privacy label" do
      it "shows the translated privacy label for a video with a privacy_status" do
        row = payload["table_rows"].find { |r| r[:cells][1][:text] == "Alpha Video" }
        cell = row[:cells][3]
        expect(cell[:text]).to be_present
        expect(cell[:class]).to include("text-fg-faded")
      end

      it "emits an empty string when privacy_status is blank" do
        blank_video = instance_double(::Video,
                                     id: 99_999,
                                     title: "No Status",
                                     privacy_status: nil,
                                     channel: channel)
        row = described_class.call([ blank_video ], conversation: conversation)["table_rows"].first
        cell = row[:cells][3]
        expect(cell[:text]).to eq("")
        expect(cell[:class]).to include("text-fg-faded")
      end
    end

    it "includes table_heading with #, Title, Channel, Privacy labels" do
      expect(payload["table_heading"]).to eq([ "#", "Title", "Channel", "Privacy" ])
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
