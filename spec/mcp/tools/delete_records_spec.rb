require "rails_helper"
require_relative "../../../app/mcp/tools/delete_records"

RSpec.describe Mcp::Tools::DeleteRecords do
  describe "preview (no confirm)" do
    it "returns a preview structure with no state change for channels" do
      channels = Array.new(2) { create(:channel) }

      expect {
        result = described_class.call(type: "channel", ids: channels.map(&:id))
        data = JSON.parse(result.content.first[:text])

        expect(data["preview_url"]).to eq("/deletions/channel/#{channels.map(&:id).join(',')}")
        expect(data["type"]).to eq("channel")
        expect(data["total"]).to eq(2)
        expect(data["items"].size).to eq(2)
        expect(data["items"].first.keys).to include("id", "label")
        expect(data["items"].first["label"]).to eq(channels.first.channel_url)
        expect(data["not_found_ids"]).to eq([])
        expect(data["message"]).to include("Preview only")
      }.not_to change(BulkOperation, :count)

      expect(Channel.count).to eq(2)
    end

    it "returns a preview for videos with title labels" do
      channel = create(:channel)
      video = create(:video, channel: channel)

      result = described_class.call(type: "video", ids: [ video.id ])
      data = JSON.parse(result.content.first[:text])

      expect(data["preview_url"]).to eq("/deletions/video/#{video.id}")
      expect(data["type"]).to eq("video")
      expect(data["items"].first["label"]).to eq(video.title)
    end

    it 'treats confirm: "no" the same as preview' do
      channel = create(:channel)
      expect {
        described_class.call(type: "channel", ids: [ channel.id ], confirm: "no")
      }.not_to change(BulkOperation, :count)

      expect(Channel.count).to eq(1)
    end

    it "tracks not_found_ids in the preview" do
      channel = create(:channel)
      result = described_class.call(type: "channel", ids: [ channel.id, 99999 ])
      data = JSON.parse(result.content.first[:text])

      expect(data["total"]).to eq(1)
      expect(data["items"].map { |i| i["id"] }).to eq([ channel.id ])
      expect(data["not_found_ids"]).to eq([ 99999 ])
    end
  end

  describe 'confirm: "yes"' do
    it "creates a BulkOperation and enqueues BulkDeleteJob for channels" do
      channels = Array.new(2) { create(:channel) }

      expect {
        result = described_class.call(type: "channel", ids: channels.map(&:id), confirm: "yes")
        data = JSON.parse(result.content.first[:text])

        expect(data["enqueued"]).to eq(true)
        expect(data["operation_id"]).to be_present
        expect(data["status_url"]).to include("/bulk_operations/")
        expect(data["type"]).to eq("channel")
        expect(data["total"]).to eq(2)
        expect(data["not_found_ids"]).to eq([])
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.last
      expect(operation.kind).to eq("bulk_delete")
      expect(operation.bulk_operation_items.count).to eq(2)
      expect(operation.bulk_operation_items.pluck(:target_type).uniq).to eq([ "Channel" ])
      expect(BulkDeleteJob.jobs.size).to eq(1)
      expect(BulkDeleteJob.jobs.first["args"]).to eq([ operation.id ])
    end

    it "creates a BulkOperation for videos" do
      channel = create(:channel)
      video = create(:video, channel: channel)

      expect {
        described_class.call(type: "video", ids: [ video.id ], confirm: "yes")
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.last
      expect(operation.bulk_operation_items.first.target_type).to eq("Video")
    end

    it "skips missing IDs but still creates an operation for the rest" do
      channel = create(:channel)

      expect {
        result = described_class.call(type: "channel", ids: [ channel.id, 99999 ], confirm: "yes")
        data = JSON.parse(result.content.first[:text])

        expect(data["total"]).to eq(1)
        expect(data["not_found_ids"]).to eq([ 99999 ])
      }.to change(BulkOperation, :count).by(1)

      expect(BulkOperation.last.bulk_operation_items.count).to eq(1)
    end

    it "errors when no existing channels are found" do
      result = described_class.call(type: "channel", ids: [ 99999 ], confirm: "yes")
      expect(result.to_h[:isError]).to be true
    end
  end

  it "returns error for unknown type" do
    result = described_class.call(type: "playlist", ids: [ 1 ])
    expect(result.to_h[:isError]).to be true
  end

  it "returns error when ids array is empty" do
    result = described_class.call(type: "channel", ids: [])
    expect(result.to_h[:isError]).to be true
  end

  describe "input schema" do
    it "disallows additional properties" do
      schema = described_class.input_schema.to_h
      expect(schema[:additionalProperties]).to eq(false).or eq("false")
    end

    it "declares confirm as enum [yes, no]" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      confirm = props[:confirm] || props["confirm"]
      expect((confirm[:type] || confirm["type"]).to_s).to eq("string")
      expect((confirm[:enum] || confirm["enum"]).map(&:to_s)).to contain_exactly("yes", "no")
    end
  end

  describe "confirm validation" do
    it "rejects confirm=true (raw boolean)" do
      channel = create(:channel)
      result = described_class.call(type: "channel", ids: [ channel.id ], confirm: true)
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to include("must be 'yes' or 'no'")
    end

    it "rejects confirm=\"1\" (legacy value)" do
      channel = create(:channel)
      result = described_class.call(type: "channel", ids: [ channel.id ], confirm: "1")
      expect(result.to_h[:isError]).to be true
    end
  end
end
