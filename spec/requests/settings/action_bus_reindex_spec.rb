require "rails_helper"

# ADR 0018 — Action bus + cable architecture.
#
# Request-level coverage for the two reindex endpoints under the new
# action bus contract:
#
#   POST /settings/stack/meilisearch/reindex
#   POST /settings/stack/voyage/reindex
#
# The controller responds 204 no_content; the cable broadcast (from
# the job + the Sidekiq middleware) drives the UI. The 409-conflict
# path also returns 204 — the dialog closes silently on a double click
# while the lock is held (FB-149).
RSpec.describe "Settings stack reindex endpoints (ADR 0018)", type: :request do
  let!(:user) { Current.user || create(:user, :totp_enabled) }

  before { AppSetting.clear_reindex_lock! }

  describe "POST /settings/stack/meilisearch/reindex" do
    it "returns 204 no_content on success" do
      post settings_stack_meilisearch_reindex_path
      expect(response).to have_http_status(:no_content)
    end

    it "enqueues MeilisearchReindexJob when the lock is clear" do
      expect {
        post settings_stack_meilisearch_reindex_path
      }.to have_enqueued_job(MeilisearchReindexJob)
    end

    it "sets the shared reindex-running flag (layer-1 DB lock)" do
      expect(AppSetting.reindex_running?).to be(false)
      post settings_stack_meilisearch_reindex_path
      expect(AppSetting.reindex_running?).to be(true)
    end

    context "when the lock is already held" do
      before { AppSetting.start_reindex! }

      it "still returns 204 no_content (Turbo treats it as a benign no-op)" do
        post settings_stack_meilisearch_reindex_path
        expect(response).to have_http_status(:no_content)
      end

      it "does NOT enqueue a second job" do
        expect {
          post settings_stack_meilisearch_reindex_path
        }.not_to have_enqueued_job(MeilisearchReindexJob)
      end
    end
  end

  describe "POST /settings/stack/voyage/reindex" do
    it "returns 204 no_content on success" do
      post settings_stack_voyage_reindex_path
      expect(response).to have_http_status(:no_content)
    end

    it "enqueues VoyageReindexJob when the lock is clear" do
      expect {
        post settings_stack_voyage_reindex_path
      }.to have_enqueued_job(VoyageReindexJob)
    end

    it "sets the shared reindex-running flag (layer-1 DB lock)" do
      expect(AppSetting.reindex_running?).to be(false)
      post settings_stack_voyage_reindex_path
      expect(AppSetting.reindex_running?).to be(true)
    end

    context "when the lock is already held" do
      before { AppSetting.start_reindex! }

      it "still returns 204 no_content" do
        post settings_stack_voyage_reindex_path
        expect(response).to have_http_status(:no_content)
      end

      it "does NOT enqueue a second job" do
        expect {
          post settings_stack_voyage_reindex_path
        }.not_to have_enqueued_job(VoyageReindexJob)
      end
    end
  end
end
