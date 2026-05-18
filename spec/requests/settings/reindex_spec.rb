require "rails_helper"

# Lane C surface coverage — `POST /settings/reindex`.
#
# Phase 32 follow-up (2026-05-16). The `[reindex]` trigger from the
# Stack pane enqueues `ReindexAllJob`, sets the layer-1 DB flag, and
# redirects to `/settings` with a flash notice. If the flag is already
# set, the controller short-circuits with an alert and does NOT enqueue
# a second job.
#
# i18n contract (per `config/locales/settings/flashes.en.yml`):
#   - notice on success → `settings.flash.reindex_started`
#   - alert when already running → `settings.flash.reindex_in_progress`
RSpec.describe "Settings::Reindex", type: :request do
  describe "POST /settings/reindex" do
    context "when the reindex lock is clear" do
      before do
        AppSetting.clear_reindex_lock!
      end

      it "enqueues ReindexAllJob exactly once" do
        expect {
          post settings_reindex_path
        }.to have_enqueued_job(ReindexAllJob).exactly(:once)
      end

      it "sets the reindex-running flag (layer 1)" do
        expect(AppSetting.reindex_running?).to be(false)

        post settings_reindex_path

        expect(AppSetting.reindex_running?).to be(true)
      end

      it "stamps reindex_started_at" do
        post settings_reindex_path
        expect(AppSetting.reindex_started_at).to be_within(5.seconds).of(Time.current)
      end

      it "redirects to /settings" do
        post settings_reindex_path
        expect(response).to redirect_to(settings_path)
      end

      it "sets the `reindex started.` notice (i18n key resolves)" do
        post settings_reindex_path
        expect(flash[:notice]).to eq(I18n.t("settings.flash.reindex_started"))
        expect(flash[:notice]).to eq("reindex started.")
      end

      it "does not set an alert on success" do
        post settings_reindex_path
        expect(flash[:alert]).to be_nil
      end
    end

    context "when the reindex lock is already set" do
      before do
        AppSetting.start_reindex!
      end

      after do
        AppSetting.clear_reindex_lock!
      end

      it "does NOT enqueue a second ReindexAllJob" do
        expect {
          post settings_reindex_path
        }.not_to have_enqueued_job(ReindexAllJob)
      end

      it "redirects to /settings" do
        post settings_reindex_path
        expect(response).to redirect_to(settings_path)
      end

      it "sets the `reindex already in progress.` alert (i18n key resolves)" do
        post settings_reindex_path
        expect(flash[:alert]).to eq(I18n.t("settings.flash.reindex_in_progress"))
        expect(flash[:alert]).to eq("reindex already in progress.")
      end

      it "does not set a notice on the short-circuit path" do
        post settings_reindex_path
        expect(flash[:notice]).to be_nil
      end

      it "does not clear or re-stamp the existing started_at" do
        original = AppSetting.reindex_started_at
        post settings_reindex_path
        expect(AppSetting.reindex_running?).to be(true)
        expect(AppSetting.reindex_started_at).to be_within(1.second).of(original)
      end
    end

    describe "unauthenticated", :unauthenticated do
      it "redirects to /login" do
        post settings_reindex_path
        expect(response).to redirect_to(login_path)
      end

      it "does not enqueue ReindexAllJob" do
        expect {
          post settings_reindex_path
        }.not_to have_enqueued_job(ReindexAllJob)
      end

      it "does not set the reindex-running flag" do
        AppSetting.clear_reindex_lock!
        post settings_reindex_path
        expect(AppSetting.reindex_running?).to be(false)
      end
    end

    describe "friendly URL" do
      it "preserves /settings/reindex" do
        expect(settings_reindex_path).to eq("/settings/reindex")
      end
    end
  end
end
