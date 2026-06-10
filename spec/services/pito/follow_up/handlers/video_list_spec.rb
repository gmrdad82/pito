# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::VideoList do
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

  it "registers for the video_list target in :append mode" do
    expect(described_class.target).to eq("video_list")
    expect(described_class.mode).to eq(:append)
  end

  it "delegates `show <id>` to the video verb handler: detail card + enhanced message" do
    result = handler.call(event:, rest: "show ##{video.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)

    expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["body"]).to include("Boss Rush")
    expect(detail["reply_target"]).to eq("video_detail")
    expect(detail["video_id"]).to eq(video.id)
    enhanced = result.events.find { |e| e[:kind] == :enhanced }[:payload]
    expect(enhanced["body"]).to include("Boss Rush")
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
end
