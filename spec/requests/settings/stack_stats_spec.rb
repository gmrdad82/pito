require "rails_helper"

# Lane C surface coverage — `GET /settings/stack_stats`.
#
# 2026-05-18 — DR follow-up. The live `/settings` Stack pane moved from
# HTTP polling to ActionCable push. The JSON endpoint is KEPT as a
# fallback / diagnostics surface (`curl /settings/stack_stats`) and the
# wire shape is the same `StackStats::Payload` the broadcaster pushes,
# so the JS controller can read either transport identically.
#
# Contract covered:
#   - Auth-gated (unauthenticated → 302 to /login).
#   - Authenticated → 200 + JSON.
#   - Payload includes redis / voyage / postgres / meilisearch / assets
#     sections.
#   - Per-section error returns `{}` (the rescue contract in both the
#     controller action and `StackStats::Payload`).
RSpec.describe "Settings::StackStats", type: :request do
  describe "GET /settings/stack_stats" do
    context "authenticated" do
      it "returns 200 OK" do
        get settings_stack_stats_path
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON" do
        get settings_stack_stats_path
        expect(response.media_type).to eq("application/json")
      end

      it "includes the five expected top-level sections" do
        get settings_stack_stats_path
        body = JSON.parse(response.body)
        expect(body.keys).to include("redis", "voyage", "postgres", "meilisearch", "assets")
      end

      it "delegates to StackStats::Payload" do
        payload = {
          redis: { busy: 0 },
          voyage: { embedded_games_count: 1 },
          postgres: { games_rows: 7 },
          meilisearch: { games_docs: 3 },
          assets: { cover_arts_files: 2 }
        }
        allow(StackStats::Payload).to receive(:call).and_return(payload)

        get settings_stack_stats_path

        body = JSON.parse(response.body)
        expect(body["redis"]).to eq("busy" => 0)
        expect(body["postgres"]).to eq("games_rows" => 7)
      end

      it "swallows a Payload error and returns the empty-section fallback" do
        allow(StackStats::Payload).to receive(:call).and_raise(StandardError, "boom")

        get settings_stack_stats_path

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).to eq(
          "redis" => {},
          "voyage" => {},
          "postgres" => {},
          "meilisearch" => {},
          "assets" => {}
        )
      end

      it "logs a warning when Payload raises (does not silently drop the error)" do
        allow(StackStats::Payload).to receive(:call).and_raise(StandardError, "boom")
        expect(Rails.logger).to receive(:warn).with(/settings#stack_stats.*boom/)

        get settings_stack_stats_path
      end
    end

    describe "unauthenticated", :unauthenticated do
      it "redirects to /login" do
        get settings_stack_stats_path
        expect(response).to redirect_to(login_path)
      end

      it "does not invoke StackStats::Payload" do
        expect(StackStats::Payload).not_to receive(:call)
        get settings_stack_stats_path
      end
    end

    describe "friendly URL" do
      it "preserves /settings/stack_stats" do
        expect(settings_stack_stats_path).to eq("/settings/stack_stats")
      end
    end
  end
end
