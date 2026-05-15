require "rails_helper"

# Phase 7.5 §11g — Channel Change History request spec.
#
# Happy / sad / edge / flaw coverage per the spec-pyramid sweep.
# Inherits the default-signed-in behavior from `spec/support/auth.rb`;
# the unauthenticated branch is asserted explicitly.
RSpec.describe "Channels::ChangeLogs", type: :request do
  let(:user)    { User.first || create(:user) }
  let(:channel) { create(:channel) }

  describe "GET /channels/:channel_id/history" do
    context "happy path — HTML" do
      let!(:older) do
        create(:channel_change_log,
               channel: channel,
               changed_by_user: user,
               field: "title",
               old_value: "Older title",
               new_value: "Middle title",
               changed_at: 3.days.ago)
      end
      let!(:newer) do
        create(:channel_change_log,
               channel: channel,
               changed_by_user: user,
               field: "handle",
               old_value: "@old",
               new_value: "@new",
               changed_at: 1.hour.ago)
      end

      it "returns 200" do
        get channel_change_logs_path(channel)
        expect(response).to have_http_status(:ok)
      end

      it "renders the H1 with the channel display title" do
        get channel_change_logs_path(channel)
        expect(response.body).to include("change history")
      end

      # 2026-05-11 — the explanatory lead paragraph was dropped per user
      # direction. The page is read-only by construction; the H1 + table
      # speak for themselves.
      it "does NOT render the dropped lead paragraph" do
        get channel_change_logs_path(channel)
        expect(response.body).not_to include("title and handle edits are appended here automatically.")
        expect(response.body).not_to include("pito does not edit or delete past entries.")
      end

      it "renders the column headers" do
        get channel_change_logs_path(channel)
        expect(response.body).to include(">field<")
        expect(response.body).to include("changed at")
        expect(response.body).to include("changed by")
      end

      it "renders rows newest first" do
        get channel_change_logs_path(channel)
        idx_newer = response.body.index("@new")
        idx_older = response.body.index("Middle title")
        expect(idx_newer).to be < idx_older
      end

      it "renders the user username in the changed_by cell" do
        get channel_change_logs_path(channel)
        expect(response.body).to include(user.username)
      end

      it "wraps the page body in pane--standalone" do
        get channel_change_logs_path(channel)
        expect(response.body).to include("pane pane--standalone")
      end

      it "renders the [changes] page without a [previous] / [next] link when only one page" do
        get channel_change_logs_path(channel)
        expect(response.body).not_to include(">previous<")
        expect(response.body).not_to include(">next<")
      end
    end

    context "happy path — JSON" do
      let!(:log) do
        create(:channel_change_log,
               channel: channel,
               changed_by_user: user,
               field: "title",
               old_value: "Old",
               new_value: "New",
               changed_at: 1.hour.ago)
      end

      it "returns 200 with the envelope shape" do
        get channel_change_logs_path(channel, format: :json)
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.keys).to include("changes", "pagination")
        expect(json["changes"]).to be_an(Array)
        expect(json["pagination"]).to include(
          "page" => 1,
          "per_page" => Channels::ChangeLogsController::PER_PAGE,
          "total" => 1,
          "total_pages" => 1
        )
      end

      it "includes per-row keys per the locked contract" do
        get channel_change_logs_path(channel, format: :json)
        row = JSON.parse(response.body)["changes"].first
        expect(row.keys).to contain_exactly(
          "id", "field", "old_value", "new_value", "changed_at", "changed_by"
        )
      end

      it "encodes changed_by as { id, username } when the FK resolves" do
        get channel_change_logs_path(channel, format: :json)
        row = JSON.parse(response.body)["changes"].first
        expect(row["changed_by"]).to eq("id" => user.id, "username" => user.username)
      end

      it "always encodes changed_by as { id, username } in steady state (FK is NOT NULL at DB level)" do
        get channel_change_logs_path(channel, format: :json)
        row = JSON.parse(response.body)["changes"].first
        expect(row["changed_by"]).to eq("id" => user.id, "username" => user.username)
      end

      it "encodes changed_at as ISO-8601 UTC" do
        get channel_change_logs_path(channel, format: :json)
        row = JSON.parse(response.body)["changes"].first
        expect(row["changed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
      end

      it "does not expose created_at on the row" do
        get channel_change_logs_path(channel, format: :json)
        row = JSON.parse(response.body)["changes"].first
        expect(row).not_to have_key("created_at")
      end
    end

    context "sad path" do
      it "returns 404 when the channel slug does not resolve" do
        get "/channels/no-such-channel/history"
        expect(response).to have_http_status(:not_found)
      end

      it "redirects to /login when unauthenticated", :unauthenticated do
        get channel_change_logs_path(channel)
        expect(response).to redirect_to(login_path)
      end
    end

    context "edge — empty state" do
      it "renders the muted `no changes yet` line when the channel has no rows" do
        get channel_change_logs_path(channel)
        expect(response.body).to include("no changes yet")
      end

      it "JSON branch returns an empty changes array" do
        get channel_change_logs_path(channel, format: :json)
        json = JSON.parse(response.body)
        expect(json["changes"]).to eq([])
        expect(json["pagination"]["total"]).to eq(0)
        expect(json["pagination"]["total_pages"]).to eq(1)
      end
    end

    context "edge — pagination" do
      before do
        # 55 rows so page 1 has 50, page 2 has 5.
        55.times do |i|
          create(:channel_change_log,
                 channel: channel,
                 changed_by_user: user,
                 field: "title",
                 old_value: "t#{i}",
                 new_value: "t#{i + 1}",
                 changed_at: i.hours.ago)
        end
      end

      it "renders 50 rows on page 1" do
        get channel_change_logs_path(channel)
        expect(response.body).to include("page 1 / 2")
      end

      it "renders 5 rows on page 2" do
        get channel_change_logs_path(channel, page: 2)
        expect(response.body).to include("page 2 / 2")
      end

      it "JSON page 1 returns 50 rows" do
        get channel_change_logs_path(channel, page: 1, format: :json)
        json = JSON.parse(response.body)
        expect(json["changes"].size).to eq(50)
      end

      it "JSON page 2 returns 5 rows" do
        get channel_change_logs_path(channel, page: 2, format: :json)
        json = JSON.parse(response.body)
        expect(json["changes"].size).to eq(5)
      end

      it "renders [next] on page 1" do
        get channel_change_logs_path(channel)
        expect(response.body).to match(/>\s*next\s*</)
      end

      it "renders [previous] on page 2" do
        get channel_change_logs_path(channel, page: 2)
        expect(response.body).to match(/>\s*previous\s*</)
      end

      it "out-of-range page renders empty body, NOT 404" do
        get channel_change_logs_path(channel, page: 999)
        expect(response).to have_http_status(:ok)
      end

      it "negative page floors at 1" do
        get channel_change_logs_path(channel, page: -5)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("page 1 / 2")
      end

      it "JSON pagination meta tracks the page" do
        get channel_change_logs_path(channel, page: 2, format: :json)
        json = JSON.parse(response.body)
        expect(json["pagination"]).to include(
          "page" => 2,
          "per_page" => 50,
          "total" => 55,
          "total_pages" => 2
        )
        expect(json["changes"].size).to eq(5)
      end
    end

    context "flaw — XSS" do
      it "escapes script payloads in old_value / new_value" do
        create(:channel_change_log,
               channel: channel,
               changed_by_user: user,
               field: "title",
               old_value: "<script>alert('xss-old')</script>",
               new_value: "<script>alert('xss-new')</script>",
               changed_at: 1.hour.ago)
        get channel_change_logs_path(channel)
        # Raw <script> tag must NOT survive into the response body.
        expect(response.body).not_to include("<script>alert('xss-old')</script>")
        expect(response.body).not_to include("<script>alert('xss-new')</script>")
        # The escaped literal text MUST appear.
        expect(response.body).to include("&lt;script&gt;alert(&#39;xss-old&#39;)&lt;/script&gt;")
        expect(response.body).to include("&lt;script&gt;alert(&#39;xss-new&#39;)&lt;/script&gt;")
      end
    end
  end
end
