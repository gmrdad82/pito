require "rails_helper"

# Phase 7 Path A2 (literal full retract). The legacy `syncing` boolean
# is gone — Phase 8+ will own in-flight state via the BulkOperation
# surface itself. The "already syncing — skipped" pre-mark logic is
# retired; every syncable record is just `pending`.
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
        expect(response.body).not_to match(/<button[^>]*btn-danger/)
        expect(response.body).to include("[sync]")
      end

      it "redirects when no items found" do
        get syncs_path(type: "channel", ids: "99999")
        expect(response).to redirect_to(channels_path)
      end

      it "does NOT render a [skip] badge (the syncing column is gone)" do
        get syncs_path(type: "channel", ids: channel.id)
        expect(response.body).not_to include("[skip]")
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

  # 2026-05-11 polish (Fix 1) — sync show page polish.
  #
  # The action-screen table on `/syncs/:type/:ids`:
  #   * renders narrow column widths via a `<colgroup>` (mirrors
  #     `/projects` and `/games` list-mode); the table sheds its
  #     legacy `width: 100%` and uses `max-content` so it shrinks
  #     to the natural width of its cells.
  #   * renames the `starred` column header to the shorter `star`.
  describe "GET /syncs (preview) — Fix 1 (2026-05-11) page polish" do
    let!(:channel) { create(:channel) }
    let!(:video)   { create(:video) }

    it "renames the channel-mode `starred` header to `star`" do
      get syncs_path(type: "channel", ids: channel.id)
      expect(response.body).to match(%r{<th class="num">\s*star\s*</th>})
      expect(response.body).not_to match(%r{<th class="num">\s*starred\s*</th>})
    end

    it "drops `width: 100%` from the channel-mode table" do
      get syncs_path(type: "channel", ids: channel.id)
      table_tag = response.body[%r{<table[^>]*>}]
      expect(table_tag).not_to be_nil
      # The legacy table carried `style="width: 100%"`. The polished
      # version uses `width: max-content; max-width: 100%`. Assert the
      # OPENING tag's style attribute does not declare `width: 100%`
      # outright (negative-lookahead-style regex to exclude the
      # `max-width: 100%` substring that legitimately remains).
      expect(table_tag).not_to match(/[^-]width:\s*100%/)
      expect(table_tag).to include("width: max-content")
      expect(table_tag).to include("max-width: 100%")
    end

    it "renders a `<colgroup>` with narrow per-column widths for channel mode" do
      get syncs_path(type: "channel", ids: channel.id)
      doc = Nokogiri::HTML.fragment(response.body)
      cols = doc.css("table > colgroup > col")
      # action gutter + URL + star + synced = 4 cols
      expect(cols.length).to eq(4)
      # The first `<col>` is the action gutter (narrow %), the rest
      # carry explicit pixel widths so the columns stay compact.
      widths = cols.map { |c| c["style"].to_s }
      expect(widths[0]).to include("1%")
      expect(widths[1]).to include("360px") # URL
      expect(widths[2]).to include("60px")  # star
      expect(widths[3]).to include("90px")  # synced
    end

    it "renders a `<colgroup>` for video mode" do
      get syncs_path(type: "video", ids: video.id)
      doc = Nokogiri::HTML.fragment(response.body)
      cols = doc.css("table > colgroup > col")
      # action gutter + YouTube id + channel = 3 cols
      expect(cols.length).to eq(3)
    end

    it "drops `width: 100%` from the video-mode table" do
      get syncs_path(type: "video", ids: video.id)
      table_tag = response.body[%r{<table[^>]*>}]
      expect(table_tag).not_to be_nil
      expect(table_tag).not_to match(/[^-]width:\s*100%/)
      expect(table_tag).to include("width: max-content")
    end
  end

  describe "GET /syncs (preview, JSON)" do
    let!(:syncable_a) { create(:channel) }
    let!(:syncable_b) { create(:channel) }

    it "returns the BulkOperationResponse preview shape (every found record is syncable)" do
      get syncs_path(type: "channel", ids: "#{syncable_a.id},#{syncable_b.id}", format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      data = JSON.parse(response.body)
      expect(data["mode"]).to eq("preview")
      expect(data["total"]).to eq(2)
      expect(data["operation_id"]).to be_nil
      expect(data["syncable"]).to contain_exactly(syncable_a.id, syncable_b.id)
      expect(data["skipped"]).to eq([])
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
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 JSON when no items match" do
      get syncs_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /syncs (enqueue, JSON)" do
    let!(:syncable_a) { create(:channel) }
    let!(:syncable_b) { create(:channel) }

    it "creates a bulk_sync operation and returns the BulkOperationResponse enqueued shape" do
      expect {
        post syncs_path(type: "channel", ids: "#{syncable_a.id},#{syncable_b.id}", format: :json)
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
    end

    it "succeeds without an authenticity token (CSRF skipped for JSON)" do
      ActionController::Base.allow_forgery_protection = true
      begin
        post syncs_path(type: "channel", ids: syncable_a.id, format: :json)
        expect(response).to have_http_status(:accepted)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end
    end

    it "returns 422 JSON for unknown type" do
      post syncs_path(type: "invalid", ids: "1", format: :json)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 JSON when no items match" do
      post syncs_path(type: "channel", ids: "99999", format: :json)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
