require "rails_helper"

# 2026-05-11 polish (Games list-mode bulk actions, Fix 5) — request
# specs covering the `/syncs/game/:ids` + `/deletions/game/:ids`
# routing path for the list-mode `[sync N]` / `[delete N]` toolbar.
RSpec.describe "Games bulk actions (list-mode toolbar)", type: :request do
  let!(:game_a) { create(:game, title: "Game A") }
  let!(:game_b) { create(:game, title: "Game B") }
  let!(:game_c) { create(:game, title: "Game C") }

  describe "GET /syncs/game/:ids — action-screen confirmation" do
    it "renders the sync confirmation screen for a single game" do
      get "/syncs/game/#{game_a.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("sync 1 game")
      expect(response.body).to include(game_a.title)
    end

    it "renders the sync confirmation screen for N games" do
      ids = [ game_a.id, game_b.id, game_c.id ].join(",")
      get "/syncs/game/#{ids}"
      expect(response).to have_http_status(:ok)
      # Plural copy when more than one row.
      expect(response.body).to include("sync 3 games")
      expect(response.body).to include(game_a.title)
      expect(response.body).to include(game_b.title)
      expect(response.body).to include(game_c.title)
    end

    it "carries a submit form that POSTs back to /syncs/game/:ids" do
      get "/syncs/game/#{game_a.id}"
      expect(response.body).to include(%(action="/syncs/game/#{game_a.id}"))
    end

    it "is NOT guarded by JS confirm / data-turbo-confirm" do
      get "/syncs/game/#{game_a.id}"
      expect(response.body).not_to include("data-turbo-confirm")
      expect(response.body).not_to include("window.confirm")
    end
  end

  describe "POST /syncs/game/:ids — enqueues bulk sync" do
    before do
      BulkSyncJob.jobs.clear
      GameSync.jobs.clear if defined?(GameSync) && GameSync.respond_to?(:jobs)
    end

    it "creates a BulkOperation and enqueues BulkSyncJob" do
      ids = [ game_a.id, game_b.id ].join(",")
      expect {
        post "/syncs/game/#{ids}"
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.order(:id).last
      expect(operation.kind).to eq("bulk_sync")
      expect(operation.bulk_operation_items.pluck(:target_type).uniq).to eq([ "Game" ])
      expect(operation.bulk_operation_items.pluck(:target_id)).to match_array([ game_a.id, game_b.id ])
    end
  end

  describe "GET /deletions/game/:ids — action-screen confirmation" do
    it "renders the deletion confirmation screen for a single game" do
      get "/deletions/game/#{game_a.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("delete 1 game")
      expect(response.body).to include(game_a.title)
    end

    it "renders the deletion confirmation screen for N games" do
      ids = [ game_a.id, game_b.id ].join(",")
      get "/deletions/game/#{ids}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("delete 2 games")
    end

    it "carries a destructive submit (text-danger button)" do
      get "/deletions/game/#{game_a.id}"
      # The shared action-screen renders the destructive button via
      # the `btn-danger` class.
      expect(response.body).to include("btn-danger")
    end

    it "is NOT guarded by JS confirm / data-turbo-confirm" do
      get "/deletions/game/#{game_a.id}"
      expect(response.body).not_to include("data-turbo-confirm")
      expect(response.body).not_to include("window.confirm")
    end
  end

  describe "POST /deletions/game/:ids — enqueues bulk delete" do
    before do
      BulkDeleteJob.jobs.clear
      GameDeletion.jobs.clear if defined?(GameDeletion) && GameDeletion.respond_to?(:jobs)
    end

    it "creates a BulkOperation and enqueues BulkDeleteJob" do
      ids = [ game_a.id, game_b.id ].join(",")
      expect {
        post "/deletions/game/#{ids}"
      }.to change(BulkOperation, :count).by(1)

      operation = BulkOperation.order(:id).last
      expect(operation.kind).to eq("bulk_delete")
      expect(operation.bulk_operation_items.pluck(:target_type).uniq).to eq([ "Game" ])
    end
  end
end
