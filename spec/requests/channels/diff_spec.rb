require "rails_helper"

# Phase 7.5 §11i — Channel diff resolution request specs.
RSpec.describe "Channels diff", type: :request do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "Local Title",
           description: "Local Description",
           youtube_connection: connection)
  end

  describe "GET /channels/:slug/diff" do
    context "with an open diff" do
      let!(:diff) do
        create(:channel_diff, channel: channel, field_diffs: {
          "title" => { "pito" => "Local Title", "youtube" => "Remote Title" }
        })
      end

      it "renders the diff page with 200" do
        get diff_channel_path(channel)
        expect(response).to have_http_status(:ok)
      end

      it "shows both column values in the response body" do
        get diff_channel_path(channel)
        expect(response.body).to include("Local Title")
        expect(response.body).to include("Remote Title")
      end

      it "renders the radio group with accept youtube as the default" do
        get diff_channel_path(channel)
        expect(response.body).to include("decisions[title]")
        expect(response.body).to match(
          %r{<input[^>]*name="decisions\[title\]"[^>]*value="youtube"[^>]*checked}
        )
      end

      it "renders the bracketed [ apply changes ] submit" do
        get diff_channel_path(channel)
        expect(response.body).to include("apply changes")
      end

      it "renders the [ cancel ] link back to the channel show" do
        get diff_channel_path(channel)
        expect(response.body).to include("cancel")
        expect(response.body).to include(channel_path(channel))
      end

      it "returns JSON parity on the .json branch" do
        get diff_channel_path(channel, format: :json)
        json = JSON.parse(response.body)
        expect(json["diff_id"]).to eq(diff.id)
        expect(json["fields"]).to eq([ "title" ])
        expect(json["writable_fields"]).to include("title")
        expect(json["unsupported_pito_fields"]).to include("banner_url")
      end
    end

    context "with no open diff" do
      it "redirects to the channel show with a flash notice" do
        get diff_channel_path(channel)
        expect(response).to redirect_to(channel_path(channel))
        follow_redirect!
        expect(response.body).to include("no open diff")
      end

      it "JSON branch returns 404 with a clear error envelope" do
        get diff_channel_path(channel, format: :json)
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)).to eq("error" => "no_open_diff")
      end
    end

    context "with a stale slug" do
      let!(:diff) do
        create(:channel_diff, channel: channel, field_diffs: {
          "title" => { "pito" => "p", "youtube" => "y" }
        })
      end

      it "301-redirects to the canonical slug when called by integer id" do
        get diff_channel_path(id: channel.id)
        expect(response).to have_http_status(:moved_permanently)
        expect(response.location).to end_with(diff_channel_path(channel))
      end
    end

    context "auth boundary" do
      it "redirects to /login when unauthenticated", :unauthenticated do
        get diff_channel_path(channel)
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "PATCH /channels/:slug/apply_diff" do
    let!(:diff) do
      create(:channel_diff, channel: channel, field_diffs: {
        "title" => { "pito" => "Local Title", "youtube" => "Remote Title" }
      })
    end

    context "happy: youtube-wins applied" do
      it "updates the local column and redirects with the success flash" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube" } }
        expect(response).to redirect_to(channel_path(channel))
        follow_redirect!
        expect(response.body).to include("changes applied")
        channel.reload
        expect(channel.title).to eq("Remote Title")
      end

      it "marks the ChannelDiff resolved" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube" } }
        diff.reload
        expect(diff).to be_resolved
        expect(diff.resolution_payload["title"]).to eq(
          { "decision" => "youtube", "value" => "Remote Title" }
        )
      end

      it "JSON branch returns ok:true with the field counts" do
        patch apply_diff_channel_path(channel, format: :json),
              params: { decisions: { "title" => "youtube" } }.to_json,
              headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["ok"]).to be(true)
        expect(json["youtube_wins_fields"]).to eq([ "title" ])
        expect(json["pito_wins_fields"]).to eq([])
      end
    end

    context "happy: pito-wins applied" do
      let(:client) { instance_double(Youtube::Client) }

      before do
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
        allow(client).to receive(:update_channel)
      end

      it "calls Youtube::Client#update_channel with the title payload" do
        expect(client).to receive(:update_channel).with(channel, hash_including(title: "Local Title"))
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "pito" } }
      end

      it "writes a ChannelChangeLog row for the title push" do
        expect {
          patch apply_diff_channel_path(channel),
                params: { decisions: { "title" => "pito" } }
        }.to change(ChannelChangeLog.where(field: "title"), :count).by(1)
      end

      it "leaves the local title unchanged (pito-wins keeps local)" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "pito" } }
        expect(channel.reload.title).to eq("Local Title")
      end
    end

    context "happy: mixed pito + youtube decisions" do
      let(:multi_diff) do
        create(:channel_diff, channel: channel, field_diffs: {
          "title"       => { "pito" => "Local Title",       "youtube" => "Remote Title" },
          "description" => { "pito" => "Local Description", "youtube" => "Remote Description" }
        })
      end
      let(:client) { instance_double(Youtube::Client) }

      before do
        diff.destroy! # remove the single-field diff from the outer let!
        multi_diff
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
        allow(client).to receive(:update_channel)
      end

      it "pushes pito-wins via the client and writes youtube-wins locally" do
        expect(client).to receive(:update_channel).with(channel, hash_including(description: "Local Description"))
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube", "description" => "pito" } }
        channel.reload
        expect(channel.title).to eq("Remote Title")
      end

      it "redirects with a success flash mentioning the field counts" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube", "description" => "pito" } }
        follow_redirect!
        expect(response.body).to include("pushed to youtube")
        expect(response.body).to include("updated locally")
      end
    end

    context "sad: extra key not in field_diffs" do
      it "re-renders with 422 and a stale_diff error" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube", "ghost" => "youtube" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("ghost").or include("changed while")
      end
    end

    context "sad: missing required key" do
      let!(:multi_diff) do
        diff.destroy!
        create(:channel_diff, channel: channel, field_diffs: {
          "title"       => { "pito" => "p", "youtube" => "y" },
          "description" => { "pito" => "p2", "youtube" => "y2" }
        })
      end

      it "re-renders with 422 and a missing-decisions error" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("no decision")
        expect(response.body).to include("description")
      end
    end

    context "sad: invalid decision value" do
      it "re-renders with 422 and an invalid-decision error" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "maybe" } }
        expect(response).to have_http_status(:unprocessable_content)
        # The single quotes around `pito` / `youtube` are HTML-escaped
        # in the flash toast (`&#39;`), so match the unquoted phrase.
        expect(response.body).to include("decision must be").and include("pito").and include("youtube")
      end
    end

    context "flaw: race — diff already resolved by another user" do
      before do
        diff.update!(resolved_at: 1.minute.ago,
                     resolution_payload: { "title" => { "decision" => "youtube" } })
      end

      it "redirects to the channel show with the already-resolved flash" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube" } }
        expect(response).to redirect_to(channel_path(channel))
        follow_redirect!
        expect(response.body).to include("already resolved").or include("no open diff")
      end
    end

    context "flaw: partial-failure on push (Q3) — transaction rolls back" do
      let(:client) { instance_double(Youtube::Client) }
      let(:multi_diff) do
        create(:channel_diff, channel: channel, field_diffs: {
          "title"       => { "pito" => "Local Title",       "youtube" => "Remote Title" },
          "description" => { "pito" => "Local Description", "youtube" => "Remote Description" }
        })
      end

      before do
        diff.destroy!
        multi_diff
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client)
        allow(client).to receive(:update_channel).and_raise(
          Youtube::QuotaExhaustedError.new("quota busted")
        )
      end

      it "re-renders the diff page with 422 and the failing-field flash" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "pito", "description" => "pito" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("could not push")
        expect(response.body).to include("no changes applied")
      end

      it "rolls back ALL changes (channel unchanged, no audit rows, diff unresolved)" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "pito", "description" => "pito" } }
        channel.reload
        expect(channel.title).to eq("Local Title")
        expect(ChannelChangeLog.where(channel: channel).count).to eq(0)
        expect(multi_diff.reload).to be_open
      end
    end

    context "flaw: bypass — unsupported pito field" do
      let!(:banner_diff) do
        diff.destroy!
        create(:channel_diff, channel: channel, field_diffs: {
          "banner_url" => { "pito" => "p", "youtube" => "y" }
        })
      end

      it "returns 422 with the unsupported_pito_field error code on accept_pito" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "banner_url" => "pito" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("cannot push")
      end

      it "still allows accept_youtube on banner_url (no push needed)" do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "banner_url" => "youtube" } }
        expect(response).to redirect_to(channel_path(channel))
      end
    end

    context "auth boundary" do
      it "redirects to /login when unauthenticated", :unauthenticated do
        patch apply_diff_channel_path(channel),
              params: { decisions: { "title" => "youtube" } }
        expect(response).to redirect_to(login_path)
      end
    end
  end
end
