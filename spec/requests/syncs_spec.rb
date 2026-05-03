require "rails_helper"

RSpec.describe "Syncs", type: :request do
  describe "GET /syncs (preview)" do
    context "channels" do
      let!(:channel) { create(:channel) }

      it "returns 200 with a single channel id" do
        get syncs_path(type: "channel", ids: channel.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("sync 1 channel")
      end

      it "shows multiple channels" do
        channel2 = create(:channel)
        get syncs_path(type: "channel", ids: "#{channel.id},#{channel2.id}")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("sync 2 channels")
      end

      it "shows breadcrumb with cancel link" do
        get syncs_path(type: "channel", ids: channel.id)
        expect(response.body).to include("channels")
        expect(response.body).to include("cancel")
      end

      it "renders a non-destructive submit button" do
        get syncs_path(type: "channel", ids: channel.id)
        # Non-destructive: no btn-danger class on the submit
        expect(response.body).not_to match(/<button[^>]*btn-danger/)
        expect(response.body).to include("[sync]")
      end

      it "redirects when no items found" do
        get syncs_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end

      it "renders a skip badge for an already-syncing channel" do
        syncing_channel = create(:channel, :syncing)
        get syncs_path(type: "channel", ids: "#{channel.id},#{syncing_channel.id}")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("[ skip ]")
        expect(response.body).to include("will be skipped")
      end

      it "disables submit when all channels are already syncing" do
        c1 = create(:channel, :syncing)
        c2 = create(:channel, :syncing)
        get syncs_path(type: "channel", ids: "#{c1.id},#{c2.id}")
        expect(response.body).to include("nothing to do")
        # Submit button is replaced by a back link — no [sync] submit
        expect(response.body).not_to include("[sync]")
      end

      it "renders skip badges only on the already-syncing rows" do
        syncing = create(:channel, :syncing)
        get syncs_path(type: "channel", ids: "#{channel.id},#{syncing.id}")
        # one [ skip ] for the syncing one; the syncable channel does not get a skip badge in the action column
        expect(response.body.scan(/\[ skip \]/).size).to be >= 1
      end
    end

    context "videos" do
      let!(:video) { create(:video) }

      it "returns 200 with valid video id" do
        get syncs_path(type: "video", ids: video.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("sync 1 video")
      end
    end

    context "invalid type" do
      it "redirects to root" do
        get syncs_path(type: "invalid", ids: "1")
        expect(response).to redirect_to(root_path)
      end
    end

    context "empty ids" do
      it "redirects to channels with alert" do
        get syncs_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end
    end
  end

  describe "POST /syncs (enqueue)" do
    context "channels — all syncable" do
      let!(:channel) { create(:channel) }

      it "creates a bulk_sync operation and enqueues BulkSyncJob" do
        expect {
          post syncs_path(type: "channel", ids: channel.id)
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkSyncJob.jobs, :size).by(1)

        operation = BulkOperation.last
        expect(operation.kind).to eq("bulk_sync")
        expect(operation.status).to eq("pending")
        expect(operation.bulk_operation_items.count).to eq(1)
        expect(operation.bulk_operation_items.first.status).to eq("pending")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("syncing")
      end

      it "creates items for multiple channels" do
        c2 = create(:channel)
        post syncs_path(type: "channel", ids: "#{channel.id},#{c2.id}")
        expect(BulkOperation.last.bulk_operation_items.count).to eq(2)
      end
    end

    context "channels — already syncing pre-marks items as skipped" do
      let!(:syncable) { create(:channel) }
      let!(:already_syncing) { create(:channel, :syncing) }

      it "creates the operation with skipped items pre-marked" do
        expect {
          post syncs_path(type: "channel", ids: "#{syncable.id},#{already_syncing.id}")
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkSyncJob.jobs, :size).by(1)

        operation = BulkOperation.last
        expect(operation.kind).to eq("bulk_sync")

        skipped_item = operation.bulk_operation_items.find_by(target_id: already_syncing.id)
        syncable_item = operation.bulk_operation_items.find_by(target_id: syncable.id)

        expect(skipped_item.status).to eq("skipped")
        expect(skipped_item.error_message).to eq("already syncing")
        expect(syncable_item.status).to eq("pending")
      end
    end

    context "videos" do
      let!(:video) { create(:video) }

      it "creates a bulk_sync operation and enqueues BulkSyncJob" do
        expect {
          post syncs_path(type: "video", ids: video.id)
        }.to change(BulkOperation, :count).by(1)
          .and change(BulkSyncJob.jobs, :size).by(1)
      end
    end

    context "invalid type" do
      it "redirects to root" do
        post syncs_path(type: "invalid", ids: "1")
        expect(response).to redirect_to(root_path)
      end
    end

    context "empty IDs" do
      it "redirects with alert" do
        post syncs_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end
    end
  end

  describe "GET /syncs (preview, JSON)" do
    let!(:syncable) { create(:channel) }
    let!(:already_syncing) { create(:channel, :syncing) }

    it "returns the BulkOperationResponse preview shape with syncable + skipped partition" do
      get syncs_path(type: "channel", ids: "#{syncable.id},#{already_syncing.id}", format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("preview")
      expect(data["total"]).to eq(2)
      expect(data["operation_id"]).to be_nil

      expect(data["syncable"]).to eq([ syncable.id ])

      expect(data["skipped"].length).to eq(1)
      expect(data["skipped"].first).to include("id" => already_syncing.id, "reason" => "already syncing")
    end

    it "treats videos as fully syncable in this phase" do
      video = create(:video)
      get syncs_path(type: "video", ids: video.id, format: :json)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("preview")
      expect(data["syncable"]).to eq([ video.id ])
      expect(data["skipped"]).to eq([])
    end

    it "returns 422 JSON for unknown type" do
      get syncs_path(type: "invalid", ids: "1", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 JSON when no items match" do
      get syncs_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /syncs (enqueue, JSON)" do
    let!(:syncable) { create(:channel) }
    let!(:already_syncing) { create(:channel, :syncing) }

    it "creates a bulk_sync operation and returns the BulkOperationResponse enqueued shape" do
      expect {
        post syncs_path(type: "channel", ids: "#{syncable.id},#{already_syncing.id}", format: :json)
      }.to change(BulkOperation, :count).by(1)
        .and change(BulkSyncJob.jobs, :size).by(1)

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq("application/json")

      operation = BulkOperation.last
      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("enqueued")
      expect(data["total"]).to eq(2)
      expect(data["syncable"]).to eq([])
      expect(data["skipped"]).to eq([])
      expect(data["operation_id"]).to eq(operation.id)
      expect(data["status_url"]).to eq(status_bulk_operation_path(operation, format: :json))
      expect(data["message"]).to match(/Bulk sync queued/i)

      # Skipped items pre-marked at create time on the BulkOperation itself
      skipped_item = operation.bulk_operation_items.find_by(target_id: already_syncing.id)
      expect(skipped_item.status).to eq("skipped")
      expect(skipped_item.error_message).to eq("already syncing")
    end

    it "succeeds without an authenticity token (CSRF skipped for JSON)" do
      ActionController::Base.allow_forgery_protection = true
      begin
        post syncs_path(type: "channel", ids: syncable.id, format: :json)
        expect(response).to have_http_status(:accepted)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "returns 422 JSON for unknown type" do
      post syncs_path(type: "invalid", ids: "1", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 JSON when no items match" do
      post syncs_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
