require "rails_helper"

RSpec.describe "BulkOperations", type: :request do
  describe "GET /bulk_operations/:id" do
    let!(:operation) { create(:bulk_operation, kind: :bulk_delete, status: :completed, completed_at: Time.current) }

    it "returns 200" do
      get bulk_operation_path(operation)
      expect(response).to have_http_status(:ok)
    end

    it "shows operation kind and status" do
      get bulk_operation_path(operation)
      expect(response.body).to include("delete")
      expect(response.body).to include("completed")
    end

    it "shows items table" do
      video = create(:video, title: "MyVid")
      operation.bulk_operation_items.create!(target: video, target_type: "Video", target_id: video.id, status: :succeeded)
      get bulk_operation_path(operation)
      # Phase 12 — Video carries title again. The view surface prefers
      # title; falls back to youtube_video_id only when title is blank.
      expect(response.body).to include("MyVid")
      expect(response.body).to include("succeeded")
    end

    it "shows deleted items gracefully" do
      operation.bulk_operation_items.create!(target_type: "Video", target_id: 99999, status: :succeeded)
      get bulk_operation_path(operation)
      expect(response.body).to include("(deleted)")
    end

    it "subscribes to turbo stream" do
      get bulk_operation_path(operation)
      expect(response.body).to include("turbo-cable-stream-source")
    end

    it "shows progress bar" do
      get bulk_operation_path(operation)
      expect(response.body).to include("operation_progress")
    end

    it "returns 404 for unknown operation" do
      get bulk_operation_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /bulk_operations/:id/status (JSON)" do
    let!(:video) { create(:video) }
    let!(:operation) { create(:bulk_operation, kind: :bulk_delete, status: :pending) }

    before do
      operation.bulk_operation_items.create!(target: video, target_type: "Video", target_id: video.id, status: :pending)
    end

    it "returns JSON with operation status and items" do
      get status_bulk_operation_path(operation, format: :json)
      expect(response).to have_http_status(:ok)

      data = JSON.parse(response.body)
      expect(data["id"]).to eq(operation.id)
      expect(data["kind"]).to eq("bulk_delete")
      expect(data["status"]).to eq("pending")
      expect(data["total"]).to eq(1)
      expect(data["current"]).to eq(0)
      expect(data["completed_at"]).to be_nil
      expect(data["items"].length).to eq(1)
      item = data["items"].first
      expect(item["status"]).to eq("pending")
      expect(item["target_id"]).to eq(video.id)
      expect(item["target_type"]).to eq("Video")
      expect(item).to have_key("error_message")
    end

    it "reflects completed state when job finishes before cable connects" do
      # Simulate job completing
      BulkDeleteJob.new.perform(operation.id)

      get status_bulk_operation_path(operation, format: :json)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("completed")
      expect(data["current"]).to eq(1)
      expect(data["completed_at"]).to be_present
      expect(data["items"].first["status"]).to eq("succeeded")
    end

    it "counts skipped items toward current progress" do
      operation.bulk_operation_items.create!(target_type: "Video", target_id: 99_999, status: :skipped, error_message: "already syncing")
      get status_bulk_operation_path(operation, format: :json)
      data = JSON.parse(response.body)
      expect(data["total"]).to eq(2)
      expect(data["current"]).to eq(1)
    end

    it "exposes error_message on failed items" do
      operation.bulk_operation_items.create!(target_type: "Video", target_id: 12_345, status: :failed, error_message: "boom")
      get status_bulk_operation_path(operation, format: :json)
      data = JSON.parse(response.body)
      failed = data["items"].find { |i| i["status"] == "failed" }
      expect(failed["error_message"]).to eq("boom")
    end

    it "returns 404 for unknown operation" do
      get status_bulk_operation_path(id: 99999, format: :json)
      expect(response).to have_http_status(:not_found)
    end
  end
end
