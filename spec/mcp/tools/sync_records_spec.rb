require "rails_helper"
require_relative "../../../app/mcp/tools/sync_records"

RSpec.describe Mcp::Tools::SyncRecords do
  describe "preview (no confirm)" do
    it "partitions ids into syncable / skipped / not_found" do
      idle = create(:channel)
      syncing = create(:channel, :syncing)

      expect {
        result = described_class.call(type: "channel", ids: [ idle.id, syncing.id, 99999 ])
        data = JSON.parse(result.content.first[:text])

        expect(data["preview_url"]).to eq("/syncs/channel/#{idle.id},#{syncing.id},99999")
        expect(data["type"]).to eq("channel")
        expect(data["total"]).to eq(3)
        expect(data["syncable"].map { |c| c["id"] }).to eq([ idle.id ])
        expect(data["syncable"].first["label"]).to eq(idle.channel_url)
        expect(data["skipped"].map { |c| c["id"] }).to eq([ syncing.id ])
        expect(data["skipped"].first["reason"]).to eq("already syncing")
        expect(data["skipped"].first["label"]).to eq(syncing.channel_url)
        expect(data["not_found_ids"]).to eq([ 99999 ])
        expect(data["message"]).to include("Preview only")
      }.not_to change(BulkOperation, :count)
    end

    it 'treats confirm: "no" the same as preview' do
      channel = create(:channel)
      expect {
        described_class.call(type: "channel", ids: [ channel.id ], confirm: "no")
      }.not_to change(BulkOperation, :count)
    end
  end

  describe 'confirm: "yes"' do
    it "creates a BulkOperation (kind: bulk_sync) and enqueues BulkSyncJob" do
      idle = create(:channel)
      syncing = create(:channel, :syncing)

      BulkSyncJob.jobs.clear if defined?(BulkSyncJob)

      expect {
        result = described_class.call(type: "channel", ids: [ idle.id, syncing.id ], confirm: "yes")
        data = JSON.parse(result.content.first[:text])

        expect(data["enqueued"]).to eq(true)
        expect(data["operation_id"]).to be_present
        expect(data["status_url"]).to include("/bulk_operations/")
        expect(data["type"]).to eq("channel")
        expect(data["syncable_count"]).to eq(1)
        expect(data["skipped_count"]).to eq(1)
        expect(data["not_found_ids"]).to eq([])
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.last
      expect(operation.kind).to eq("bulk_sync")
      expect(operation.bulk_operation_items.count).to eq(2)

      idle_item = operation.bulk_operation_items.find_by(target_id: idle.id)
      syncing_item = operation.bulk_operation_items.find_by(target_id: syncing.id)
      expect(idle_item.status).to eq("pending")
      expect(syncing_item.status).to eq("skipped")
      expect(syncing_item.error_message).to eq("already syncing")

      expect(BulkSyncJob.jobs.size).to eq(1)
      expect(BulkSyncJob.jobs.first["args"]).to eq([ operation.id ])
    end

    it "errors when all ids are missing" do
      result = described_class.call(type: "channel", ids: [ 99999 ], confirm: "yes")
      expect(result.to_h[:isError]).to be true
    end

    it "creates an operation when all ids are already syncing (all items pre-marked skipped)" do
      a = create(:channel, :syncing)
      b = create(:channel, :syncing)

      expect {
        result = described_class.call(type: "channel", ids: [ a.id, b.id ], confirm: "yes")
        data = JSON.parse(result.content.first[:text])

        expect(data["syncable_count"]).to eq(0)
        expect(data["skipped_count"]).to eq(2)
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.last
      expect(operation.bulk_operation_items.pluck(:status).uniq).to eq([ "skipped" ])
    end

    it "tracks not_found_ids alongside syncable items" do
      idle = create(:channel)

      result = described_class.call(type: "channel", ids: [ idle.id, 99999 ], confirm: "yes")
      data = JSON.parse(result.content.first[:text])

      expect(data["syncable_count"]).to eq(1)
      expect(data["not_found_ids"]).to eq([ 99999 ])
    end
  end

  describe "video type" do
    it "returns a structured error since video sync isn't supported yet" do
      result = described_class.call(type: "video", ids: [ 1 ])
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to include("not yet supported")
    end

    it 'rejects video type even with confirm: "yes"' do
      result = described_class.call(type: "video", ids: [ 1 ], confirm: "yes")
      expect(result.to_h[:isError]).to be true
    end
  end

  it "errors with empty ids" do
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
